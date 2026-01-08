//
//  ARViewContainer.swift
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
