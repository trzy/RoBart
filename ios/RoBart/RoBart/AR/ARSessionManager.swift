//
//  ARSessionManager.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
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
import Combine
import MultipeerConnectivity
import RealityKit
import SwiftUI

class ARSessionManager: ObservableObject {
    static let shared = ARSessionManager()

    @Published fileprivate(set) var participantCount = 0
    @Published fileprivate(set) var remoteAnchor = WeakRef<ARAnchor>()

    var session: ARSession? {
        return arView?.session
    }

    var scene: RealityKit.Scene? {
        return arView?.scene
    }

    fileprivate let frameSubject = CurrentValueSubject<ARFrame?, Never>(nil)
    let frames: AnyPublisher<ARFrame, Never>

    var renderPlanes: Bool = false {
        didSet {
            _sceneMeshRenderer.renderPlanes = renderPlanes
        }
    }

    var renderWorldMeshes: Bool = false {
        didSet {
            _sceneMeshRenderer.renderWorldMeshes = renderWorldMeshes
        }
    }

    var sceneUnderstanding: Bool = true {
        didSet {
            // Restart session in case anything changed
            startSession(preserveAnchors: true)
        }
    }

    private(set) var transform: Matrix4x4 = .identity

    var headingDegrees: Float {
        let forward = -transform.forward.xzProjected    // -transform.forward is direction of rear cam
        let angle = Vector3.signedAngle(from: .forward, to: forward, axis: .up)
        return angle >= 0 ? angle : (360 + angle)
    }

    func direction(fromDegrees degrees: Float) -> Vector3 {
        return Vector3.forward.rotated(by: degrees, about: .up)
    }

    var floorY: Float {
        // Use actual value if we have it
        if let floorY = _floorY {
            return floorY
        }

        // Otherwise need to estimate
        if Settings.shared.role == .robot {
            return -Calibration.phoneHeightAboveFloor
        } else {
            // Use a sensible default for someone standing and holding a phone
            return -1.5
        }
    }

    var sceneMeshes: [SceneMesh] {
        return _sceneMeshRenderer.getMeshes()
    }

    var velocity: Vector3 {
        return _motionEstimator.velocity
    }

    var speed: Float {
        return _motionEstimator.speed
    }

    var acceleration: Vector3 {
        return _motionEstimator.acceleration
    }

    var angularVelocity: Float {
        return _motionEstimator.angularVelocity
    }

    var angularSpeed: Float {
        return abs(_motionEstimator.angularVelocity)
    }

    fileprivate weak var arView: ARView?
    fileprivate let _motionEstimator = MotionEstimator()
    private var _subscriptions = Set<AnyCancellable>()
    fileprivate let _sceneMeshRenderer = SceneMeshRenderer()
    fileprivate let _participantRenderer = ParticipantRenderer()
    private var _floorY: Float? = nil

    fileprivate init() {
        // Allows multiple callers to nextFrame() to share a frame
        self.frames = frameSubject.compactMap { $0 }.share().eraseToAnyPublisher()

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

    func startSession(preserveAnchors: Bool = false) {
        startSession(collaborative: PeerManager.shared.peers.count > 0, preserveAnchors: preserveAnchors)
    }

    private func startSession(collaborative: Bool, preserveAnchors: Bool = false) {
        guard let arView = arView else { return }

        // New session configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = sceneUnderstanding ? [ .horizontal ] : []
        config.environmentTexturing = .none
        config.isCollaborationEnabled = collaborative
        if Settings.shared.role == .robot && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = sceneUnderstanding ? .mesh : []
        }

        // Start session only if configuration changed
        if let existingConfig = arView.session.configuration as? ARWorldTrackingConfiguration {
            if existingConfig == config {
                log("Session already running with proper configuration")
                return
            }
        }
        arView.session.run(config, options: preserveAnchors ? [] : .removeExistingAnchors)
        log("Started session with collaboration \(collaborative ? "enabled" : "disabled") and scene depth \(config.frameSemantics.contains(.sceneDepth) ? "enabled" : "disabled")")
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

    private func updateFloorPlane(from anchors: [ARAnchor]) {
        for anchor in anchors {
            if let plane = anchor as? ARPlaneAnchor,
               plane.alignment == .horizontal {
                // Record the minimum y of horizontal planes. If device supports plane
                // classification, then only use planes detected to be floor planes.
                let y = plane.transform.position.y
                var sample = true
                if ARPlaneAnchor.isClassificationSupported && plane.classification != .floor {
                    sample = false
                }
                if sample {
                    if _floorY == nil {
                        _floorY = y
                        log("Floor Y estimate updated: \(_floorY!)")
                    } else {
                        let delta = abs(_floorY! - y)
                        if delta >= 0.1 {
                            _floorY = min(_floorY!, y)
                            log("Floor Y estimate updated: \(_floorY!)")
                        }
                    }
                }
            }
        }
    }

    /// SwiftUI coordinator instantiated in the SwiftUI `ARViewContainer` to run the ARKit session.
    class Coordinator: NSObject, ARSessionDelegate {
        private let _parentView: ARViewContainer

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
            ARSessionManager.shared.updateFloorPlane(from: anchors)
            ARSessionManager.shared._sceneMeshRenderer.addMeshes(from: anchors, to: arView)
            ARSessionManager.shared._participantRenderer.addParticipants(from: anchors, to: arView)
            ARSessionManager.shared.participantCount = ARSessionManager.shared._participantRenderer.participantCount

            // Publish remote anchors (excluding participant anchors)
            for anchor in anchors {
                if anchor.sessionIdentifier != session.identifier,
                   (anchor as? ARParticipantAnchor) == nil {
                    ARSessionManager.shared.remoteAnchor = WeakRef(object: anchor)
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            ARSessionManager.shared.updateFloorPlane(from: anchors)
            ARSessionManager.shared._sceneMeshRenderer.updateMeshes(from: anchors)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            ARSessionManager.shared._sceneMeshRenderer.removeMeshes(for: anchors)
            ARSessionManager.shared._participantRenderer.removeParticipants(for: anchors)
            ARSessionManager.shared.participantCount = ARSessionManager.shared._participantRenderer.participantCount
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
