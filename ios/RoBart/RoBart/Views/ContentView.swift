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

    @State private var _depthImage: UIImage?

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
                            Button("Drive To", action: placeDriveToAnchor)
                                .disabled(_cursor == nil || _settings.role != .phone)
                                .padding()
                            Button("STOP", action: stopHoverboard)
                                .padding()
                            Button("Render", action: {
                                if let pixels = ARSessionManager.shared.renderOrthoDepth() {
                                    print("DEPTH: \(pixels.count) pixels")
                                    //_depthImage = createUIImage(from: pixels, width: 64, height: 64)
                                    for i in 0..<pixels.count {
                                        print("\(i) = \(pixels[i])")
                                    }
                                } else {
                                    print("DEPTH: FAILED!")
                                }
                            })
                                .padding()
                            Spacer()
                        }
                        .buttonStyle(.bordered)
                        CollaborativeMappingStateView()
                    }
                }
                if let depthImage = _depthImage {
                    Image(uiImage: depthImage)
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
                    .disabled(_settings.role != .robot)

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
        }
    }

    private func updateRaycast(event: SceneEvents.Update, arView: ARView) {
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
        let anchor = ARAnchor(name: "Drive Here", transform: worldTransform)
        ARSessionManager.shared.session?.add(anchor: anchor)
    }

    private func handleRemoteAnchor(_ anchor: ARAnchor) {
        if anchor.name == "Drive Here" {
            // Drive to anchor received from remote
            log("Driving to remote anchor")
            HoverboardController.send(.driveTo(position: anchor.transform.position))
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
        let msg = PeerMotorMessage(leftMotorThrottle: 0, rightMotorThrottle: 0)
        PeerManager.shared.send(msg, toPeersWithRole: .robot, reliable: true)
    }

    private func createUIImage(from floatArray: [Float], width: Int, height: Int) -> UIImage? {
        // Ensure the array has the correct number of elements
        guard floatArray.count == width * height else {
            print("Array size does not match width * height")
            return nil
        }

        // Create a buffer to store pixel data (RGBA)
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        // Convert float array (0.0 to 1.0) to RGBA pixel data
        for i in 0..<(width * height) {
            let value = floatArray[i]
            let grayscale = UInt8(value * 255)  // Convert float [0.0, 1.0] to [0, 255]

            // Set the pixel (grayscale, so same value for R, G, B, and full opacity for A)
            pixelData[i * 4] = grayscale     // Red
            pixelData[i * 4 + 1] = grayscale // Green
            pixelData[i * 4 + 2] = grayscale // Blue
            pixelData[i * 4 + 3] = 255       // Alpha
        }

        // Create a CGImage from pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let provider = CGDataProvider(data: NSData(bytes: &pixelData, length: pixelData.count * MemoryLayout<UInt8>.size))

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        // Convert CGImage to UIImage
        return UIImage(cgImage: cgImage)
    }
}

fileprivate func log(_ message: String) {
    print("[ContentView] \(message)")
}

#Preview {
    ContentView()
}
