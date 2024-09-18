//
//  VoiceExtractor.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//

import AVFoundation
import WebRTCVAD

class VoiceExtractor {
    private static let _chunkSeconds: Double = 30e-3            // WebRTC VAD is run on chunks of this size
    private static let _detectionWindowSeconds: Double = 300e-3 // time window over which a voice classification decision is made (integral multiple of chunk size)
    private static let _endpointSeconds: Double = 510e-3        // amount of silence required to endpoint speech (integral multiple of chunk size)
    private static let _minimumSpeechSeconds: Double = 510e-3   // minimum amount of speech for a detection to be valid

    private var _windowBuffer: AVAudioPCMBuffer?                // circular buffer that holds a detection window's worth of audio
    private var _nextWindowWriteIdx: AVAudioFrameCount = 0      // next position to copy an analyzed input chunk to
    private var _totalWindowFramesWritten: AVAudioFrameCount = 0    // total number written (which will exceed window size once it fills up)
    private var _framesPerChunk: AVAudioFrameCount = 0          // number of frames in a single chunk (populated when window buffer allocated)
    private var _partialChunkFramesWritten: AVAudioFrameCount = 0   // number of frames written if last data appended was not a full chunk

    private var _voiceChunks: [Bool]                            // circular buffer indicating which chunks in window detected as voice
    private var _nextChunkIdx = 0

    private var _vad: WebRTCVAD?

    private var _insideSpeech = false
    private var _framesWrittenToOutput: AVAudioFrameCount = 0
    private var _speechFramesWrittenToOutput: AVAudioFrameCount = 0
    private var _silentFramesDetected: AVAudioFrameCount = 0
    private var _silentEndpointFrames: AVAudioFrameCount = 0
    private var _minimumSpeechFrames: AVAudioFrameCount = 0


    init() {
        assert(Self._chunkSeconds < Self._detectionWindowSeconds)
        assert(Self._chunkSeconds < Self._endpointSeconds)

        // Detection window must be an integral multiple of the chunk size so we can both safely
        // copy one chunk at a time and maintain a list of detection results per-chunk. We never
        // have to worry about the rolling window wrapping mid-chunk!
        let numWindowChunks = Int(ceil(Self._detectionWindowSeconds / Self._chunkSeconds))
        assert(numWindowChunks > 0)

        // Silence threshold must also be an integral multiple of chunk size
        let numSilentChunks = Int(ceil(Self._endpointSeconds / Self._chunkSeconds))
        assert(numSilentChunks > 0)

        _voiceChunks = Array(repeating: false, count: numWindowChunks)
    }

    func reset() {
        _windowBuffer?.frameLength = 0
        _nextWindowWriteIdx = 0
        _totalWindowFramesWritten = 0
        _partialChunkFramesWritten = 0

        for i in 0..<_voiceChunks.count {
            _voiceChunks[i] = false
        }
        _nextChunkIdx = 0

        _insideSpeech = false
        _framesWrittenToOutput = 0
        _speechFramesWrittenToOutput = 0
        _silentFramesDetected = 0
    }

    /// Processes a segment of incoming audio and once voiced samples are detected, appends those to `outputSpeechBuffer`.
    /// When end of speech is detected, or when the output buffer is filled, returns a non-zero frame count to indicate the total length
    /// of speech detected. The state is then reset and the caller must reset the output buffer before the next call.
    /// - Parameter outputSpeechBuffer: The buffer to which voiced frames will be written, beginning at frame 0.
    /// - Parameter inputAudioBuffer: The next samples in the stream of input to process.
    /// - Returns: 0 if no complete voiced segment is yet available, otherwise the number of frames from the beginning of the
    /// output buffer that contain a complete speech segment. The state is reset as soon as a non-zero value is returned.
    func process(outputSpeechBuffer speechBuffer: AVAudioPCMBuffer, inputAudioBuffer buffer: AVAudioPCMBuffer) -> AVAudioFrameCount {
        assert(buffer.format == speechBuffer.format)
        
        guard let windowBuffer = getWindowBuffer(format: buffer.format) else {
            return 0
        }

        let vad = getVAD(format: buffer.format)

        /*
         * Processing is performed one VAD chunk at a time.
         *
         * 1. Copy up to a chunk's worth of data into the window. If we have less than a chunk,
         *    record the partial amount and finish.
         * 2. Classify the chunk as voice or not.
         * 3. Once the window fills, we assess whether it is speech or not. If so, we copy
         *    everything to the outputSpeechBuffer and transition to the speech state.
         * 4. While in the speech state, we continue to append chunks to the rolling window and
         *    perform voice detection each time. We also incrementally append chunks to the
         *    output. We wait for the threshold amount of non-speech before returning a detction.
         */

        var inputIdx = AVAudioFrameCount(0)

        while inputIdx < buffer.frameLength && speechBuffer.frameLength < speechBuffer.frameCapacity {
            // Append to rolling window
            let (chunkStartIdx, framesAppended) = appendToWindow(from: buffer, fromIdx: inputIdx)
            inputIdx += framesAppended
            if framesAppended == 0 ||
               _partialChunkFramesWritten > 0 ||    // exhausted input and only copied a partial chunk
               !haveFullWindow() {                  // don't yet have a full window to analyze
                break
            }

            // Classify last chunk appended
            _voiceChunks[_nextChunkIdx] = vad.isVoice(buffer: windowBuffer, from: chunkStartIdx)
            _nextChunkIdx = (_nextChunkIdx + 1) % _voiceChunks.count

            // Are we inside speech or not? Assess entire window.
            let wasInsideSpeech = _insideSpeech
            let nowInsideSpeech = windowIsSpeech()
            
            if nowInsideSpeech {
                _insideSpeech = nowInsideSpeech

                // Reset endpoint detection
                _silentFramesDetected = 0
            }

            if nowInsideSpeech || wasInsideSpeech {
                // Copy to output speech buffer. If we just transitioned to a non-speech chunk, we
                // still copy until conversation endpoint threshold is reached.
                let outputFull = copyLatestToOutput(speechBuffer, isSpeech: nowInsideSpeech)
                if outputFull {
                    // We have filled up the output buffer. Reset state and return a detection.
                    let speechFrames = _speechFramesWrittenToOutput
                    reset()
                    if speechFrames >= _minimumSpeechFrames {
                        return speechFrames
                    }
                    continue
                }
            } 

            if !nowInsideSpeech && wasInsideSpeech {
                // We are still inside a speech segment until endpoint silence threshold is
                // reached
                _silentFramesDetected += _framesPerChunk
                if _silentFramesDetected >= _silentEndpointFrames {
                    // Enough silence has elapsed to endpoint the speech segment
                    let speechFrames = _speechFramesWrittenToOutput
                    reset()
                    if speechFrames >= _minimumSpeechFrames {
                        return speechFrames
                    }
                    continue
                }
            }
        }

        return 0
    }

    private func getWindowBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if let buffer = _windowBuffer {
            assert(buffer.format == format) // format mustn't change
            return buffer
        }

        _framesPerChunk = AVAudioFrameCount(ceil(format.sampleRate * Self._chunkSeconds))
        _silentEndpointFrames = AVAudioFrameCount(ceil(format.sampleRate * Self._endpointSeconds))
        _minimumSpeechFrames = AVAudioFrameCount(ceil(format.sampleRate * Self._minimumSpeechSeconds))

        let numChunks = _voiceChunks.count
        let numFrames = AVAudioFrameCount(numChunks) * _framesPerChunk
        if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: numFrames) {
            _windowBuffer = buffer
            return buffer
        }

        log("Error: Unable to create rolling window buffer")
        return nil
    }

    private func getVAD(format: AVAudioFormat) -> WebRTCVAD {
        if _vad == nil {
            _vad = WebRTCVAD(aggressiveness: .MostAggressive, inputAudioFormat: format, chunkSeconds: Self._chunkSeconds)
        }
        return _vad!
    }

    private func appendToWindow(from buffer: AVAudioPCMBuffer, fromIdx: AVAudioFrameCount) -> (AVAudioFrameCount, AVAudioFrameCount) {
        guard let windowBuffer = _windowBuffer else { return (AVAudioFrameCount(0), AVAudioFrameCount(0)) }
        
        if _partialChunkFramesWritten > 0 {
            // We are adding to a partially completed chunk. We only want to fill up the chunk!
            let chunkStartIdx = _nextWindowWriteIdx - _partialChunkFramesWritten
            let numFramesMissingFromChunk = _framesPerChunk - _partialChunkFramesWritten
            let numFrames = min(numFramesMissingFromChunk, buffer.frameLength - fromIdx)
            windowBuffer.safeCopyWithResize(destIdx: _nextWindowWriteIdx, from: buffer, srcIdx: fromIdx, frameCount: numFrames)
            if numFrames < numFramesMissingFromChunk {
                // We *still* don't have a full chunk!
                _partialChunkFramesWritten += numFrames
            } else {
                // Full chunk acquired
                _partialChunkFramesWritten = 0
            }
            _nextWindowWriteIdx = (_nextWindowWriteIdx + numFrames) % windowBuffer.frameCapacity
            _totalWindowFramesWritten += numFrames
            return (chunkStartIdx, numFrames)
        } else {
            // New chunk
            let chunkStartIdx = _nextWindowWriteIdx
            let numFrames = min(_framesPerChunk, buffer.frameLength - fromIdx)
            windowBuffer.safeCopyWithResize(destIdx: _nextWindowWriteIdx, from: buffer, srcIdx: fromIdx, frameCount: numFrames)
            if numFrames < _framesPerChunk {
                // Did not write a full chunk
                _partialChunkFramesWritten = numFrames
            } else {
                _partialChunkFramesWritten = 0
            }
            _nextWindowWriteIdx = (_nextWindowWriteIdx + numFrames) % windowBuffer.frameCapacity
            _totalWindowFramesWritten += numFrames
            return (chunkStartIdx, numFrames)
        }
    }

    private func haveFullWindow() -> Bool {
        guard let windowBuffer = _windowBuffer else { return false }
        return windowBuffer.frameLength == windowBuffer.frameCapacity
    }

    private func windowIsSpeech() -> Bool {
        let numVoiceChunks = _voiceChunks.reduce(Int(0), { (current: Int, next: Bool) in current + (next == true ? 1 : 0) })
        let percentVoice = Float(numVoiceChunks) / Float(_voiceChunks.count)
        let thresholdPercent: Float = 0.9
        return percentVoice >= thresholdPercent
    }

    /// Copies the latest frames added to window buffer to output speech buffer. If we are inside a
    /// speech segment but the latest chunk has resulted in the window transitioning from speech to
    /// non-speech, `isSpeech` should be set false. We append this in case speech resumes before
    /// the endpoint threshold is reached but we temporarily stop counting speech frames written.
    /// If the endpoint is eventually reached, those silent frames will then not be counted in the
    /// overall speech segment.
    private func copyLatestToOutput(_ outputSpeechBuffer: AVAudioPCMBuffer, isSpeech: Bool) -> Bool {
        guard let windowBuffer = _windowBuffer else { return outputSpeechBuffer.frameLength == outputSpeechBuffer.frameCapacity }

        // How many frames -- the entire window or just the last frame?
        if _totalWindowFramesWritten < windowBuffer.frameCapacity {
            // We shouldn't even be here!
            return outputSpeechBuffer.frameLength == outputSpeechBuffer.frameCapacity
        } else {
            // Window was already full
            if outputSpeechBuffer.frameLength == 0 {
                // This is the first time we are writing to the output and therefore the first
                // time that speech detection has triggered. We need to copy out the whole window,
                // and this may require a split transfer if we have already wrapped around.
                let srcIdx1 = _nextWindowWriteIdx   // the next write position is also the oldest position written because this is a circular buffer
                let numFrames1 = windowBuffer.frameCapacity - srcIdx1
                let srcIdx2 = AVAudioFrameCount(0)
                let numFrames2 = srcIdx1 - srcIdx2
                outputSpeechBuffer.safeCopyWithResize(destIdx: outputSpeechBuffer.frameLength, from: windowBuffer, srcIdx: srcIdx1, frameCount: numFrames1)
                outputSpeechBuffer.safeCopyWithResize(destIdx: outputSpeechBuffer.frameLength, from: windowBuffer, srcIdx: srcIdx2, frameCount: numFrames2)
            } else {
                // Initial window of detection was already copied, now we are just writing
                // an incremental chunk
                if _nextWindowWriteIdx == 0 {
                    // We wrapped, take last chunk in window
                    outputSpeechBuffer.safeCopyWithResize(destIdx: outputSpeechBuffer.frameLength, from: windowBuffer, srcIdx: windowBuffer.frameCapacity - _framesPerChunk, frameCount: _framesPerChunk)
                } else {
                    outputSpeechBuffer.safeCopyWithResize(destIdx: outputSpeechBuffer.frameLength, from: windowBuffer, srcIdx: _nextWindowWriteIdx - _framesPerChunk, frameCount: _framesPerChunk)
                }
            }
        }

        // Was this sub-segment actually speech or not?
        if isSpeech {
            _speechFramesWrittenToOutput = outputSpeechBuffer.frameLength
        }

        // Return whether the output has been filled up
        return outputSpeechBuffer.frameLength == outputSpeechBuffer.frameCapacity
    }
}

fileprivate func log(_ message: String) {
    print("[VoiceExtractor] \(message)")
}
