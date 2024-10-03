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
    private var _lastAudioClipEndTime: CMTime = .zero

    private var _audioMixer: AVMutableComposition?
    private var _audioTrack: AVMutableCompositionTrack?

    init(outputSize: CGSize, frameRate: Int32) {
        self._outputSize = outputSize
        self._frameRate = frameRate
    }

    func startRecording() throws {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("output.mp4")
        try? FileManager.default.removeItem(at: outputURL)  // just in case we crashed and a file is still there
        _assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: _outputSize.width,
            AVVideoHeightKey: _outputSize.height,
        ]

        _videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        _videoInput?.expectsMediaDataInRealTime = true

        let rotationTransform = CGAffineTransform(rotationAngle: .pi / 2)   // vertical orientation
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

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        _audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        _audioInput?.expectsMediaDataInRealTime = false // audio is composed into a track and copied to video when we finish recording
        _audioMixer = AVMutableComposition()
        _audioTrack = _audioMixer!.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        _assetWriter?.add(_videoInput!)
        _assetWriter?.add(_audioInput!)
        _assetWriter?.startWriting()
        _assetWriter?.startSession(atSourceTime: .zero)

        _currentTime = .zero
        _lastAudioClipEndTime = .zero
    }

    func addFrame(_ pixelBuffer: CVPixelBuffer) {
        guard CGSize(width: pixelBuffer.width, height: pixelBuffer.height) == _outputSize else { return }

        let frameTime = CMTimeMake(value: Int64(_frameCount), timescale: _frameRate)

        if _videoInput?.isReadyForMoreMediaData == true {
            _pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: frameTime)
            _frameCount += 1
            _currentTime = frameTime
        }
    }

    func addMP3AudioClip(_ audioData: Data) async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try audioData.write(to: tempURL)

        let asset = AVAsset(url: tempURL)
        let duration = try await asset.load(.duration)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first!

        // Insert silence
        var currentAudioTime = _currentTime.convertScale(duration.timescale, method: .default)
        if CMTimeCompare(_lastAudioClipEndTime, currentAudioTime) < 0 {
            // _lastAudioClipEndTime < currentAudioTime. Safe to insert silence. Sometimes, this is
            // not true due to some sort of timing mismatch and the time range ends up NaN if so.
            let precedingSilence = CMTimeRangeFromTimeToTime(start: _lastAudioClipEndTime, end: currentAudioTime)
            _audioTrack?.insertEmptyTimeRange(precedingSilence)
            _audioTrack?.insertEmptyTimeRange(CMTimeRangeFromTimeToTime(start: currentAudioTime, end: CMTimeAdd(currentAudioTime, duration)))
            print("[VideoRecorder] \(currentAudioTime.seconds) \(duration.seconds) \(precedingSilence.start.seconds) \(precedingSilence.end.seconds) \(_lastAudioClipEndTime.seconds)")
        } else {
            currentAudioTime = _lastAudioClipEndTime
            _audioTrack?.insertEmptyTimeRange(CMTimeRangeFromTimeToTime(start: currentAudioTime, end: CMTimeAdd(currentAudioTime, duration)))
            print("[VideoRecorder] \(currentAudioTime.seconds) \(duration.seconds) \(_lastAudioClipEndTime.seconds)")
        }

        // Audio clip
        let timeRange = CMTimeRangeMake(start: .zero, duration: duration)
        try _audioTrack?.insertTimeRange(timeRange, of: audioTrack, at: currentAudioTime)

        _lastAudioClipEndTime = CMTimeAdd(currentAudioTime, duration)
    }

    func finishRecording() async throws {
        guard let videoInput = _videoInput,
              let audioInput = _audioInput,
              let audioMixer = _audioMixer,
              let audioTrack = _audioTrack else { return }

        // Video is finished
        videoInput.markAsFinished()
        print("[VideoRecorder] Total video length: \(_currentTime.seconds)")

        // Write audio
        let audioOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,  // convert to PCM from MP3
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let audioReader = try AVAssetReader(asset: audioMixer)
        let audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSettings)
        audioReader.add(audioReaderOutput)
        audioReader.startReading()

        // Read the audio from the track we composed and add it to the video
        while audioInput.isReadyForMoreMediaData == true {
            if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
                audioInput.append(sampleBuffer)
            } else {
                audioInput.markAsFinished()
                break
            }
        }

        // Write the asset file and save it to the photo library
        return try await withCheckedThrowingContinuation { continuation in
            _assetWriter?.finishWriting {
                if let error = self._assetWriter?.error {
                    print("[VideoRecorder] Error writing asset file: \(error)")
                    continuation.resume(throwing: error)
                } else if let outputURL = self._assetWriter?.outputURL {
                    self.saveVideoToPhotoLibrary(outputURL: outputURL) { error in
                        if let error = error {
                            print("[VideoRecorder] Error saving video: \(error)")
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                            print("[VideoRecorder] Saved video to photo library")
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
