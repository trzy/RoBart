//
//  ARSessionManager.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import ARKit
import Combine
import MultipeerConnectivity
import RealityKit
import SwiftUI

class ARSessionManager: ObservableObject {
    static let shared = ARSessionManager()

    @Published var participantCount = 0

    fileprivate weak var arView: ARView?

    var scene: RealityKit.Scene? {
        return arView?.scene
    }

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
        PeerManager.shared.$peers.sink { [weak self] (peers: [MCPeerID]) in
            // Update session based on whether there are peers or not.
            // Note: PeerManager.shared.peers is not updated until after this call, so must use
            // passed peers!
            self?.startSession(collaborative: peers.count > 0)
        }.store(in: &_subscriptions)

        PeerManager.shared.$receivedMessage.sink { [weak self] (received: (peerID: MCPeerID, data: Data)?) in
            guard let received = received else { return }
            self?.handlePeerMessage(received.data, from: received.peerID)
        }.store(in: &_subscriptions)
    }

    func startSession() {
        startSession(collaborative: PeerManager.shared.peers.count > 0)
    }

    private func startSession(collaborative: Bool) {
        guard let arView = arView else { return }

        // Session needs to be collaborative if peers are connected. Only start/restart the session
        // if this has changed or no session exists in the first place.
        if let existingConfig = arView.session.configuration as? ARWorldTrackingConfiguration {
            if existingConfig.isCollaborationEnabled == collaborative {
                // Session already running in proper configuration
                return
            }
        }

        // New session configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [ .horizontal, .vertical ]
        config.environmentTexturing = .none
        config.isCollaborationEnabled = collaborative
//        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
//            config.sceneReconstruction = .mesh
//        }
        arView.session.run(config, options: .removeExistingAnchors)

        log("Started session with collaboration \(collaborative ? "enabled" : "disabled")")
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

    private func handlePeerMessage(_ data: Data, from peerID: MCPeerID) {
        if let msg = PeerCollaborationMessage.deserialize(from: data),
           let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: msg.data) {
            arView?.session.update(with: collaborationData)
        }
    }

    /// SwiftUI coordinator instantiated in the SwiftUI `ARViewContainer` to run the ARKit session.
    class Coordinator: NSObject, ARSessionDelegate {
        private let _parentView: ARViewContainer
        private let _sceneMeshRenderer = SceneMeshRenderer()
        private let _participantRenderer = ParticipantRenderer()

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
            _participantRenderer.addParticipants(from: anchors, to: arView)
            ARSessionManager.shared.participantCount = _participantRenderer.participantCount
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            _sceneMeshRenderer.updateMeshes(from: anchors)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            _sceneMeshRenderer.removeMeshes(for: anchors)
            _participantRenderer.removeParticipants(for: anchors)
            ARSessionManager.shared.participantCount = _participantRenderer.participantCount
        }

        func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true) else {
                log("Failed to encode collaboration data. Session may be corrupted.")
                return
            }
            PeerManager.shared.sendToAll(PeerCollaborationMessage(data: encodedData), reliable: data.priority == .critical)
        }
    }
}

fileprivate func log(_ message: String) {
    print("[ARSessionManager] \(message)")
}
