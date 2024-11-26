//
//  SpeechDetector.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//
//  This file is part of RoBart.
//
//  RoBart is free software: you can redistribute it and/or modify it under the
//  terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version.
//
//  RoBart is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with RoBart. If not, see <http://www.gnu.org/licenses/>.
//

import Combine
import AVFoundation

class SpeechDetector: ObservableObject {
    @Published private(set) var speech: String = ""

    private let _maxSpeechSeconds = 30
    private var _speechBuffer: AVAudioPCMBuffer!
    private var _converter: AVAudioConverter?
    private let _outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
    private let _voiceExtractor = VoiceExtractor()

    private var _isListening = false

    init() {
        // Create output buffer to hold detected speech
        _speechBuffer = createSpeechBuffer(format: _outputFormat)
        guard _speechBuffer != nil else {
            fatalError("Unable to allocate speech buffer")
        }
    }

    func startListening() {
        guard !_isListening else { return }
        log("Starting speech detector")
        _isListening = true
        AudioManager.shared.startRecording() { [weak self] (buffer: AVAudioPCMBuffer, isStream: Bool) in
            guard let self = self else { return }

            // Convert audio to Deepgram and VAD format
            _converter = createConverter(from: buffer.format, to: _outputFormat)
            guard let audioBuffer = convertAudio(buffer) else { return }

            if isStream {
                // If streaming from microphone, use VAD to minimize voice uploads
                let numSpeechFrames = _voiceExtractor.process(outputSpeechBuffer: _speechBuffer, inputAudioBuffer: audioBuffer)
                if numSpeechFrames > 0 {
                    log("Detected \(Double(numSpeechFrames) / _speechBuffer.format.sampleRate) sec of speech")

                    // Send to Deepgram for transcription
                    transcribe(_speechBuffer)

                    // Reset speech buffer
                    _speechBuffer.frameLength = 0
                }
            } else {
                // We received a complete audio buffer
                transcribe(buffer)
            }
        }
    }

    func stopListening() {
        guard _isListening else { return }
        log("Stopping speech detector")
        _isListening = false
        AudioManager.shared.stopRecording()
    }

    private func createSpeechBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if _speechBuffer == nil {
            let numFrames = AVAudioFrameCount(ceil(format.sampleRate * Double(_maxSpeechSeconds)))
            _speechBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: numFrames)
            if _speechBuffer == nil {
                log("Error: Unable to allocate speech buffer")
            } else {
                log("Successfully created speech buffer with format: \(_speechBuffer!.format)")
            }
        }
        return _speechBuffer
    }

    private func createConverter(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioConverter? {
        if _converter == nil {
            _converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            if _converter == nil {
                log("Error: Unable to create audio converter!")
            }
        }
        return _converter
    }

    private func convertAudio(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = _converter else { return nil }

        let outputFrameCapacity = AVAudioFrameCount(ceil(converter.outputFormat.sampleRate / buffer.format.sampleRate) * Double(buffer.frameLength))
        guard let outputAudioBuffer = AVAudioPCMBuffer(pcmFormat: _outputFormat, frameCapacity: outputFrameCapacity) else {
            log("Error: Unable to allocate output buffer for conversion")
            return nil
        }

        var error: NSError?
        var allSamplesReceived = false
        converter.convert(to: outputAudioBuffer, error: &error, withInputFrom: { (inNumPackets: AVAudioPacketCount, outError: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            if allSamplesReceived {
                outError.pointee = .noDataNow
                return nil
            }
            allSamplesReceived = true
            outError.pointee = .haveData
            return buffer
        })

        guard error == nil else {
            log("Error: Failed to convert audio: \(error!.localizedDescription)")
            return nil
        }

        return outputAudioBuffer
    }

    private func toData(_ buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let audioBytes = audioBuffer.mData else { return nil }
        return Data(bytes: audioBytes, count: Int(audioBuffer.mDataByteSize))
    }

    private func transcribe(_ buffer: AVAudioPCMBuffer) {
        assert(buffer.format.sampleRate == 16000)
        assert(buffer.format.channelCount == 1)
        assert(buffer.format.commonFormat == AVAudioCommonFormat.pcmFormatInt16)
        let start = Date.timeIntervalSinceReferenceDate
        guard let sampleData = toData(buffer) else { return }
        _ = Task {
            if let transcript = await transcribeWithDeepgram(sampleData) {
                log("Transcript: \(transcript)")
                DispatchQueue.main.async { [weak self] in
                    self?.speech = transcript
                }
            }
            let elapsedMilliseconds = Int((Date.timeIntervalSinceReferenceDate - start) / 1e-3)
            log("Deepgram took: \(elapsedMilliseconds) ms")
        }
    }
}

fileprivate func log(_ message: String) {
    print("[SpeechDetector] \(message)")
}
