//
//  FirstPersonVideo.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/6/24.
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

import ARKit
import CoreVideo
import UIKit

actor FirstPersonVideo {
    private var _task: Task<Void, Never>?
    private var _videoRecorder: VideoRecorder?
    private var _displayState: Brain.DisplayState?
    private var _worldPointByID: [Int: Vector3] = [:]
    private var _path: [Vector3] = []

    deinit {
        _task?.cancel()
    }

    nonisolated func setDisplayState(_ state: Brain.DisplayState?) {
        Task { [weak self] in
            await self?.set(state)
        }
    }

    nonisolated func setNavigablePoints(_ photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]]) {
        Task { [weak self] in
            await self?.set(photosByNavigablePoint)
        }
    }

    nonisolated func setPath(_ path: [Vector3]) {
        Task { [weak self] in
            await self?.set(path)
        }
    }

    nonisolated func clearPath() {
        setPath([])
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

    private func set(_ photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]]) {
        for photo in photosByNavigablePoint.values.flatMap({ $0 }) {
            for point in photo.navigablePoints {
                _worldPointByID[point.id] = point.worldPoint
            }
        }
    }

    private func set(_ path: [Vector3]) {
        _path = path
    }

    private func recordVideoTask() async {
        do {
            // Wait for first frame in order to get size of image and spawn video recorder. We
            // rotate the image ourselves, so adjust the resolution accordingly here.
            guard let firstFrame = try? await ARSessionManager.shared.nextFrame() else { return }
            let resolution = CGSize(width: firstFrame.capturedImage.height, height: firstFrame.capturedImage.width)
            let targetFrameRate = Settings.shared.annotateVideos ? 10 : 20  // hack: annotations slow things down, try to match frame rate
            _videoRecorder = VideoRecorder(outputSize: resolution, frameRate: Int32(targetFrameRate))
            try await _videoRecorder?.startRecording(rotateToPortrait: false)

            // Record until exception (i.e., due to task canceled)
            while true {
                let t0 = Date.now
                try await Task.sleep(for: .milliseconds(50))
                if _displayState != .thinking {
                    let frame = try await ARSessionManager.shared.nextFrame()
                    if let pixelBuffer = rotateToPortraitAndDrawAnnotations(frame: frame) {
                        await _videoRecorder?.addFrame(pixelBuffer)
                    }
                }
            }
        } catch {
            try? await _videoRecorder?.finishRecording()
        }

        _videoRecorder = nil
    }

    private func rotateToPortraitAndDrawAnnotations(frame: ARFrame) -> CVPixelBuffer? {
        guard let image = UIImage(pixelBuffer: frame.capturedImage)?.rotatedClockwise90() else { return nil }

        if !Settings.shared.annotateVideos {
            // No annotations necessary
            return image.toPixelBuffer()
        }

        let ourPosition = frame.camera.transform.position
        let ourForward = -frame.camera.transform.forward.xzProjected.normalized
        let worldToCamera = frame.camera.transform.inverse
        let intrinsics = frame.camera.intrinsics

        guard let photo1 = AnnotatingCamera.Photo.createWithPathAnnotations(
            name: "tmp",        // don't care
            originalImage: image,
            path: _path,
            worldToCamera: worldToCamera,
            intrinsics: intrinsics,
            position: ourPosition,
            forward: ourForward,
            headingDegrees: nil
        ) else { return nil }

        var navigablePoints: [AnnotatingCamera.NavigablePoint] = []
        let dummyCell = OccupancyMap.CellIndices(0, 0)  // don't care here
        for (id, worldPoint) in _worldPointByID {
            let toPoint = worldPoint - ourPosition
            let inFrontOfCamera = Vector3.dot(ourForward, toPoint) >= 0
            if inFrontOfCamera {
                navigablePoints.append(.init(id: id, cell: dummyCell, worldPoint: worldPoint))
            }
        }

        guard let photo2 = AnnotatingCamera.Photo.createWithNavigablePointAnnotations(
            name: "tmp",        // don't care
            originalImage: photo1.annotatedImage,   // render atop previous annotations
            navigablePoints: navigablePoints,
            worldToCamera: worldToCamera,
            intrinsics: intrinsics,
            position: ourPosition,
            forward: ourForward,
            headingDegrees: nil
        ) else { return nil }

        return photo2.annotatedImage.toPixelBuffer()
    }
}

fileprivate func log(_ message: String) {
    print("[FirstPersonVideo] \(message)")
}
