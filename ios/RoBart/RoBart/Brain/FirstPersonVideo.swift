//
//  FirstPersonVideo.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/6/24.
//

import Foundation

actor FirstPersonVideo {
    private var _task: Task<Void, Never>?
    private var _videoRecorder: VideoRecorder?
    private var _displayState: Brain.DisplayState?

    deinit {
        _task?.cancel()
    }

    nonisolated func setDisplayState(to state: Brain.DisplayState?) {
        Task { [weak self] in
            await self?.set(state)
        }
    }

    func record() {
        guard _task == nil else { return }
        if Settings.shared.recordVideos {
            _task = Task {
                await recordVideoTask()
            }
        }
    }

    func finish() async {
        guard _task != nil else { return }
        _task?.cancel()
        _ = await _task?.result
        _task = nil
    }

    func addMP3AudioClip(_ mp3Data: Data) async {
        do {
            try await _videoRecorder?.addMP3AudioClip(mp3Data)
        } catch {
            log("Error: Unable to add audio to video: \(error.localizedDescription)")
        }
    }

    private func set(_ state: Brain.DisplayState?) {
        _displayState = state
    }

    private func recordVideoTask() async {
        do {
            // Wait for first frame in order to get size of image and spawn video recorder
            guard let firstFrame = try? await ARSessionManager.shared.nextFrame() else { return }
            let resolution = CGSize(width: firstFrame.capturedImage.width, height: firstFrame.capturedImage.height)
            _videoRecorder = VideoRecorder(outputSize: resolution, frameRate: 20)
            try await _videoRecorder?.startRecording()

            // Record until exception (i.e., due to task canceled)
            while true {
                try await Task.sleep(for: .milliseconds(50))
                if _displayState != .thinking {
                    let frame = try await ARSessionManager.shared.nextFrame()
                    if let capturedImage = frame.capturedImage.copy() {
                        await _videoRecorder?.addFrame(frame.capturedImage)
                    }
                }
            }
        } catch {
            try? await _videoRecorder?.finishRecording()
        }

        _videoRecorder = nil
    }
}

fileprivate func log(_ message: String) {
    print("[FirstPersonVideo] \(message)")
}
