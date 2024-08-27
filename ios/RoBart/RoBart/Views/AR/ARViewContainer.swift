//
//  ARViewContainer.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import ARKit
import Combine
import RealityKit
import SwiftUI

fileprivate var _subscription: Cancellable?

struct ARViewContainer: UIViewRepresentable {
    @State private var _onUpdate: ((SceneEvents.Update, ARView) -> Void)


    init(_ onUpdate: @escaping (SceneEvents.Update, ARView) -> Void) {
        self._onUpdate = onUpdate
    }

    func makeCoordinator() -> ARSessionManager.Coordinator {
        ARSessionManager.Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        // Create an ARView and pass it to the coordinator (which hands it to ARSessionManager)
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        // Configure and run an AR session
        ARSessionManager.shared.startSession()

        // Subscribe to update events
        _subscription = arView.scene.subscribe(to: SceneEvents.Update.self) { (event: SceneEvents.Update) in
            _onUpdate(event, arView)
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
    }
}
