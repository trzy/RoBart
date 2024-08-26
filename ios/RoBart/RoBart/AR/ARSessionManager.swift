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

    fileprivate weak var arView: ARView?

    fileprivate let frameSubject = PassthroughSubject<ARFrame, Never>()
    var frames: AnyPublisher<ARFrame, Never> {
        return frameSubject.eraseToAnyPublisher()
    }

    fileprivate let _motionEstimator = MotionEstimator()

    private(set) var transform: Matrix4x4 = .identity

    var velocity: Vector3 {
        return _motionEstimator.velocity
    }

    var acceleration: Vector3 {
        return _motionEstimator.acceleration
    }

    var angularVelocity: Float {
        return _motionEstimator.angularVelocity
    }

    private var _subscriptions = Set<AnyCancellable>()

    fileprivate init() {
        Settings.shared.$role.sink { [weak self] (role: Role) in
            // AR session configuration depends on our role
            self?.configureSession(for: role)
        }.store(in: &_subscriptions)
    }

    func configureSession(for role: Role) {
        guard let arView = arView else { return }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [ .horizontal, .vertical ]
        config.environmentTexturing = .none
//        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
//            config.sceneReconstruction = .mesh
//        }
        arView.session.run(config, options: .removeExistingAnchors)
    }

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

    /// SwiftUI coordinator instantiated in the SwiftUI `ARViewContainer` to run the ARKit session.
    class Coordinator: NSObject, ARSessionDelegate {
        private let _parentView: ARViewContainer
        private let _sceneMeshRenderer = SceneMeshRenderer()

        weak var arView: ARView? {
            didSet {
                // Pass view to the session manager so it can modify the session. This is so gross,
                // is there a better way to structure all of this?
                ARSessionManager.shared.arView = arView
            }
        }

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
