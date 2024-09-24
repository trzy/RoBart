//
//  ContentView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import ARKit
import Combine
import RealityKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings = Settings.shared
    @State private var _cursor: Entity?
    @State private var _subscription: Cancellable?
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

            Task {
                //await followPerson(duration: 10, distance: nil)
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
