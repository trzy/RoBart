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

struct ARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> ARSessionManager.Coordinator {
        ARSessionManager.Coordinator(self)
    }

    func makeUIView(context: Context) -> ARView {
        // Create an ARView and pass it to the coordinator (which hands it to ARSessionManager)
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        // Configure and run an AR session
        ARSessionManager.shared.configureSession(for: Settings.shared.role)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
    }
}
