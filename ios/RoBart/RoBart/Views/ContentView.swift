//
//  ContentView.swift
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

struct ContentView: View {
    @ObservedObject private var _settings = Settings.shared
    @ObservedObject private var _brain = Brain.shared
    @State private var _cursor: Entity?
    @State private var _subscription: Cancellable?
    @State private var _followingPersonTask: Task<Void, Never>?
    @ObservedObject private var _client = Client.shared
    @StateObject private var _depthTest = DepthTest()

    var body: some View {
        NavigationView {
            ZStack {
                ARViewContainer() { (event: SceneEvents.Update, arView: ARView) in
                    updateRaycast(event: event, arView: arView)
                }
                .edgesIgnoringSafeArea(.all)
                VStack {
                    Spacer()
                    VStack {
                        HStack {
                            // Drive to destination
                            let driveToLabel = _settings.driveToButtonUsesNavigation ? "Navigate To" : "Drive To"
                            Button(driveToLabel, action: placeDriveToAnchor)
                                .disabled(_cursor == nil || _settings.role != .handheld)
                                .padding()

                            // Toggle follow mode
                            let followModeLabel = Image(systemName: _followingPersonTask != nil ? "person.circle" : "person.slash")
                            Button {
                                toggleFollowMode()
                            } label: {
                                followModeLabel
                            }

                            // Emergency stop
                            Button("STOP", action: stopHoverboard)
                                .padding()

//                            Button("Draw", action: { _depthTest.drawPoints() })
//                                .padding()
//                            Button("Path", action: { _depthTest.testPath() })
//                                .padding()
                            Spacer()
                        }
                        .buttonStyle(.bordered)
                        CollaborativeMappingStateView()
                    }
                }

                if let brainState = _brain.displayState {
                    VStack {
                        Spacer()
                        Text(brainState.rawValue)
                            .font(.system(size: 120))
                        Spacer()
                        Spacer()
                        Spacer()
                        Spacer()
                    }
                }

                if let image = _depthTest.image {
                    VStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        Spacer()
                    }
                }

                if _settings.role == .handheld,
                   let image = _client.robotOccupancyMapImage {
                    let _ = print("Showing image")
                    VStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        Spacer()
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink {
                        HoverboardControlView()
                    } label: {
                        Image(systemName: "car.front.waves.down")
                            .imageScale(.large)
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                            .imageScale(.large)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)    // prevent landscape mode column behavior
        .onAppear {
            // Subscribe to remote anchors
            _subscription = ARSessionManager.shared.$remoteAnchor.sink { (anchor: WeakRef<ARAnchor>) in
                if let anchor = anchor.object {
                    handleRemoteAnchor(anchor)
                }
            }

            // Enable brain initially
            if _followingPersonTask == nil {
                _brain.enabled = true
            }
        }
    }

    private func updateRaycast(event: SceneEvents.Update, arView: ARView) {
        // Handheld phone raycasts to select positions for robot navigation
        guard Settings.shared.role == .handheld else { return }
        guard let query = arView.makeRaycastQuery(from: arView.center, allowing: .estimatedPlane, alignment: .any) else { return }
        if let hit = arView.session.raycast(query).first {
            let cursor = getCursor(in: event.scene)
            cursor.transform.matrix = hit.worldTransform
        }
    }

    private func placeDriveToAnchor() {
        // Create a specially named anchor that will be transmitted to robot via collaborative
        // mapping. Robot will destroy the anchor.
        guard let cursor = _cursor else { return }
        let worldTransform = cursor.transformMatrix(relativeTo: nil)
        let name = Settings.shared.driveToButtonUsesNavigation ? "Navigate Here" : "Drive Here"
        let anchor = ARAnchor(name: name, transform: worldTransform)
        ARSessionManager.shared.session?.add(anchor: anchor)
    }

    private func handleRemoteAnchor(_ anchor: ARAnchor) {
        if anchor.name == "Drive Here" {
            // Drive to anchor received from remote without using navigation
            log("Driving to remote anchor")
            HoverboardController.send(.driveTo(position: anchor.transform.position))
            ARSessionManager.shared.session?.remove(anchor: anchor)
        } else if anchor.name == "Navigate Here" {
            // Use navigation
            NavigationController.shared.run(.navigate(to: anchor.transform.position))
            ARSessionManager.shared.session?.remove(anchor: anchor)
        }
    }

    private func getCursor(in scene: RealityKit.Scene) -> Entity {
        if _cursor == nil {
            let mesh = MeshResource.generateBox(width: 0.04, height: 0.02, depth: 0.04, cornerRadius: 0.04)
            let entity = ModelEntity(mesh: mesh, materials: [ UnlitMaterial(color: .cyan) ])
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            scene.addAnchor(anchor)
            _cursor = entity
        }
        return _cursor!
    }

    private func toggleFollowMode() {
        if _followingPersonTask == nil {
            _followingPersonTask = Task {
                // Disable brain and just follow
                _brain.enabled = false
                await followPerson(duration: nil, distance: nil)
            }
        } else {
            // Re-enable brain and stop following
            _brain.enabled = true
            _followingPersonTask?.cancel()
            _followingPersonTask = nil
        }
    }

    private func stopHoverboard() {
        if Settings.shared.role == .robot {
            // We are the robot: stop immediately
            _client.stopRobot()
        } else {
            // Send to robot
            PeerManager.shared.send(PeerStopMessage(), toPeersWithRole: .robot, reliable: true)
        }
    }
}

fileprivate func log(_ message: String) {
    print("[ContentView] \(message)")
}

#Preview {
    ContentView()
}
