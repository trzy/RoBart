//
//  ARSessionManager.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import ARKit
import Combine
import RealityKit
import SwiftUI

class ARSessionManager {
    static let shared = ARSessionManager()

    fileprivate let frameSubject = PassthroughSubject<ARFrame, Never>()
    var frames: AnyPublisher<ARFrame, Never> {
        return frameSubject.eraseToAnyPublisher()
    }

    fileprivate let _motionEstimator = MotionEstimator()

    func nextFrame() async throws -> ARFrame {
        // https://medium.com/geekculture/from-combine-to-async-await-c08bf1d15b77
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = frames.first()
                .sink { result in
                    switch result {
                    case .finished:
                        break
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                } receiveValue: { value in
                    continuation.resume(with: .success(value))
                }
        }
    }

    private(set) var transform: Matrix4x4 = .identity

    var velocity: Vector3 {
        return _motionEstimator.velocity
    }

    var acceleration: Vector3 {
        return _motionEstimator.acceleration
    }

    fileprivate init() {
    }

    /// SwiftUI coordinator instantiated in the SwiftUI `ARViewContainer` to run the ARKit session.
    class Coordinator: NSObject, ARSessionDelegate {
        private let _parentView: ARViewContainer
        private let _sceneMeshRenderer = SceneMeshRenderer()

        weak var arView: ARView?

        init(_ arViewContainer: ARViewContainer) {
            _parentView = arViewContainer
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Publish frames to subscribers
            ARSessionManager.shared.transform = frame.camera.transform
            ARSessionManager.shared._motionEstimator.update(frame)
            ARSessionManager.shared.frameSubject.send(frame)
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView = arView else { return }
            _sceneMeshRenderer.addMeshes(from: anchors, to: arView)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            _sceneMeshRenderer.updateMeshes(from: anchors)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            _sceneMeshRenderer.removeMeshes(for: anchors)
        }
    }
}

