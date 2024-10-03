//
//  VideoRecorder.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/2/24.
//

import UIKit
import AVFoundation
import Photos

actor VideoRecorder {
    private var _assetWriter: AVAssetWriter?
    private var _videoInput: AVAssetWriterInput?
    private var _audioInput: AVAssetWriterInput?
    private var _pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var _frameCount: Int64 = 0
    private let _frameRate: Int32
    private let _outputSize: CGSize
    private var _currentTime: CMTime = .zero
    private var _lastAudioTime: CMTime = .zero

    init(outputSize: CGSize, frameRate: Int32) {
        self._outputSize = outputSize
        self._frameRate = frameRate
    }

    func startRecording() throws {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("output.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        _assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: _outputSize.width,
            AVVideoHeightKey: _outputSize.height,
        ]

        // Video frames expected to be added in real-time at the desired frame rate
        _videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        _videoInput?.expectsMediaDataInRealTime = true

        let rotationTransform = CGAffineTransform(rotationAngle: .pi / 2)
        _videoInput?.transform = rotationTransform

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: _outputSize.width,
            kCVPixelBufferHeightKey as String: _outputSize.height
        ]

        _pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: _videoInput!,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        // Optimized for audio appearing periodically with large gaps in between
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        _audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        _audioInput?.expectsMediaDataInRealTime = false

        _assetWriter?.add(_videoInput!)
        _assetWriter?.add(_audioInput!)
        _assetWriter?.startWriting()
        _assetWriter?.startSession(atSourceTime: .zero)

        _currentTime = .zero
        _lastAudioTime = .zero
    }

    func addFrame(_ pixelBuffer: CVPixelBuffer) {
        guard CGSize(width: pixelBuffer.width, height: pixelBuffer.height) == _outputSize else { return }

        let frameTime = CMTimeMake(value: _frameCount, timescale: _frameRate)

        if _videoInput?.isReadyForMoreMediaData == true {
            _pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: frameTime)
            _frameCount += 1
            _currentTime = frameTime    // video determines our frame timing
        }
    }

    func addMP3AudioClip(_ audioData: Data) async throws {
        // Write MP3 file to disk because there is no way to create an AVAsset from in-memory data
        // (AVFoundation sucks)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try audioData.write(to: tempURL)

        // Load the MP3 back as an AVAsset and obtain the audio
        let asset = AVAsset(url: tempURL)
        let duration = try await asset.load(.duration)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first!

        // Create a reader to read and decode the MP3 into PCM sample buffers. (Convoluted because
        // AVFoundation sucks.)
        let audioReader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        audioReader.add(audioReaderOutput)
        guard audioReader.startReading() else {
            throw NSError(domain: "AudioReaderError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to start reading audio"])
        }

        // The presentation time of this audio will be at the current frame time
        let baseInsertionTime = _currentTime.convertScale(duration.timescale, method: .default)
        print("Adding audio clip at \(baseInsertionTime.seconds) seconds, duration: \(duration.seconds) seconds")

        // Padding silence. This is completely fucked but it turns out that the very first sample
        // can be inserted at any time but subsequent samples will be inserted after the last one,
        // even if the presentation time is adjusted. So we literally have to insert silence.
        // (AVFoundation sucks!!)
        if _lastAudioTime != .zero,
           CMTimeRange(start: _lastAudioTime, end: baseInsertionTime).duration.seconds > 0,
           let silence = createSilentAudio(startTime: _lastAudioTime, endTime: baseInsertionTime, sampleRate: 44100, numChannels: 2) {
            while !_audioInput!.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            _audioInput!.append(silence)
        }

        // Read each sample buffer, adjust the presentation time stamps, and add to the audio input
        var totalAudioDuration = CMTime.zero
        while let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
            let bufferDuration = CMSampleBufferGetDuration(sampleBuffer)
            let adjustedBuffer = adjustTimeStamp(of: sampleBuffer, by: baseInsertionTime)

            while !_audioInput!.isReadyForMoreMediaData {
                // In non-realtime mode, this should never happen
                try await Task.sleep(nanoseconds: 2_000_000) // 0.02 second
            }
            _audioInput!.append(adjustedBuffer)

            totalAudioDuration = CMTimeAdd(totalAudioDuration, bufferDuration)
        }

        // Don't forget to update the audio end time so we know how much silence to write next
        // time around
        _lastAudioTime = CMTimeAdd(baseInsertionTime, totalAudioDuration)
        log("Finished adding audio clip. Last sample at: \(_lastAudioTime.seconds) seconds")
    }

    private func adjustTimeStamp(of sampleBuffer: CMSampleBuffer, by timeOffset: CMTime) -> CMSampleBuffer {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)

        var timingInfo = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &timingInfo, entriesNeededOut: nil)

        for i in 0..<count {
            timingInfo[i].presentationTimeStamp = CMTimeAdd(timingInfo[i].presentationTimeStamp, timeOffset)
            if timingInfo[i].decodeTimeStamp != .invalid {
                timingInfo[i].decodeTimeStamp = CMTimeAdd(timingInfo[i].decodeTimeStamp, timeOffset)
            } else {
                timingInfo[i].decodeTimeStamp = timingInfo[i].presentationTimeStamp
            }
        }

        var adjustedBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count, sampleTimingArray: &timingInfo, sampleBufferOut: &adjustedBuffer)

        return adjustedBuffer!
    }

    private func createSilentAudio(startTime: CMTime, endTime: CMTime, sampleRate: Int32, numChannels: UInt32) -> CMSampleBuffer? {
        let startTime = startTime.convertScale(sampleRate, method: .default)

        let bytesPerFrame = UInt32(2 * numChannels)
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        let numSeconds = timeRange.duration.seconds
        let numFrames = Int(numSeconds * Float64(sampleRate))
        let blockSize = numFrames*Int(bytesPerFrame)

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: blockSize,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: blockSize,
            flags: 0,
            blockBufferOut: &block
        )
        assert(status == kCMBlockBufferNoErr)

        guard let eBlock = block else { return nil }

        // We get zeros from the above but it isn't documented so memset to be sure
        status = CMBlockBufferFillDataBytes(with: 0, blockBuffer: eBlock, offsetIntoDestination: 0, dataLength: blockSize)
        assert(status == kCMBlockBufferNoErr)

        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: numChannels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDesc: CMAudioFormatDescription?
        status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDesc)
        assert(status == noErr)

        var sampleBuffer: CMSampleBuffer?

        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: eBlock,
            formatDescription: formatDesc!,
            sampleCount: numFrames,
            presentationTimeStamp: startTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        assert(status == noErr)
        return sampleBuffer
    }

    func finishRecording() async throws {
        _videoInput?.markAsFinished()
        _audioInput?.markAsFinished()

        return try await withCheckedThrowingContinuation { continuation in
            _assetWriter?.finishWriting {
                if let error = self._assetWriter?.error {
                    log("Error: Failed to write asset file: \(error)")
                    continuation.resume(throwing: error)
                } else if let outputURL = self._assetWriter?.outputURL {
                    self.saveVideoToPhotoLibrary(outputURL: outputURL) { error in
                        if let error = error {
                            log("Error: Failed to save video: \(error)")
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                            log("Saved video to photo library")
                        }
                    }
                } else {
                    continuation.resume(throwing: NSError(domain: "VideoCreatorError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown error occurred"]))
                }
            }
        }
    }

    private func saveVideoToPhotoLibrary(outputURL: URL, completion: @escaping (Error?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
        }) { success, error in
            try? FileManager.default.removeItem(at: outputURL)
            if success {
                completion(nil)
            } else {
                completion(error)
            }
        }
    }
}

fileprivate func log(_ message: String) {
    print("[VideoRecorder] \(message)")
}
