//
//  DepthTest.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/7/24.
//
//  Scene Depth Value to World Point
//  --------------------------------
//  - Depth image is 256x192. The camera sensor is oriented such that in the vertical orientation,
//    +x in the depth image moves vertically from top to bottom in the vertical viewfinder, and +y
//    in the depth image (moving from first row to bottom row) moves from right to left in the
//    viewfinder.
//
//      Veritcally-oriented             Depth image
//      phone
//
//      <--- +y of depth image          (0,0) --> +x
//      +----+ (0,0) of depth image     +----------------+
//      |    | |                        |                | |
//      |    | |                        |                | |
//      |    | V                        |                | V
//      |    | +x of depth image        |                | +y
//      +----+                          +----------------
//
//    The ARKit camera pose is: +x is down ([0, -1, 0]), +y is right, and +z is out of the screen.
//
//      ARKit camera coordinate system (3D)
//
//      ---> +y
//      +----+
//      |    | |
//      |    | |
//      |    | V
//      |    | +x
//      +----+
//
//    Depth values are positive. To convert them into the camera coordinate space, observe that the
//    depth image is almost the same as the ARKit coordinate system, except that +z is opposite
//    (pointing out the back side of the camera, where the LiDAR points) and y is opposite. All
//    that needs to be done is to rotate the 3D point 180 degrees about the x axis.
//
//  - Points in camera space, [x, y, z], are transformed to image space using the camera intrinsic
//    matrix as follows:
//
//      xi = fx * (x/z) + cx
//      yi = fy * (y/z) + cy
//
//    Therefore, to convert an image pixel coordinate with depth to camera space:
//
//      x = (xi - cx) * depth / fx
//      y = (yi - cy) * depth / fy
//      z = depth
//
//  - Camera intrinsics are for the RGB image, to which the scene depth is aligned. To obtain the
//    depth intrinsic matrix, simply scale fx and cx by (depthWidth/rgbWidth) and fy and cy by
//    (depthHeight/rgbHeight). Depth values (positive) are used directly, as we are operating in
//    the depth image 3D coordinate system.
//

import ARKit
import Combine
import RealityKit

class DepthTest: ObservableObject {
    @Published var image: UIImage?

    private var _subscription: Cancellable!
    private var _sceneDepth: ARDepthData?
    private var _intrinsics: Matrix3x3?
    private var _viewMatrix: Matrix4x4?
    private var _rgbResolution: CGSize?

    private let _depthWidth = 32
    private let _depthHeight = 24
    private var _entities: [Entity] = []

    private var _occupancy: OccupancyMap?

    init() {
        _subscription = ARSessionManager.shared.frames.sink { [weak self] (frame: ARFrame) in
            self?.onFrame(frame)
        }
    }

    func drawPoints() {
        guard let sceneDepth = _sceneDepth,
              let intrinsics = _intrinsics,
              let viewMatrix = _viewMatrix,
              let rgbResolution = _rgbResolution,
              let depth = sceneDepth.depthMap.resize(newWidth: _depthWidth, newHeight: _depthHeight),
              let depthValues = depth.toFloatArray(),
              _entities.count > 0 else {
            return
        }

        // Get depth intrinsic parameters
        let scaleX = Float(_depthWidth) / Float(rgbResolution.width)
        let scaleY = Float(_depthHeight) / Float(rgbResolution.height)
        let fx = intrinsics[0,0] * scaleX
        let cx = intrinsics[2,0] * scaleX   // note: (column, row)
        let fy = intrinsics[1,1] * scaleY
        let cy = intrinsics[2,1] * scaleY

        // Create a depth camera to world matrix. The depth image coordinate system happens to be
        // almost the same as the ARKit camera system, except y is flipped (everything rotated 180
        // degrees about the x axis, which points down in portrait orientation).
        let rotateDepthToARKit = Quaternion(angle: .pi, axis: .right)
        let cameraToWorld = viewMatrix * Matrix4x4(translation: .zero, rotation: rotateDepthToARKit, scale: .one)

        // Create a small cube for each point
        var idx = 0
        for yi in 0..<_depthHeight {
            for xi in 0..<_depthWidth {
                // Compute world position
                let depth = depthValues[idx]    // use positive depth directly in these calculations
                let cameraSpacePos = Vector3(x: depth * (Float(xi) - cx) / fx , y: depth * (Float(yi) - cy) / fy, z: depth)
                let worldPos = cameraToWorld.transformPoint(cameraSpacePos)

                //log("Pos=\(cameraSpacePos) Depth=\(depth)")

                // Update corresponding entity
                let anchor = _entities[idx]
                anchor.position = worldPos
                anchor.isEnabled = true
                idx += 1
            }
        }
    }

    private func onFrame(_ frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return }
        _sceneDepth = sceneDepth
        _intrinsics = frame.camera.intrinsics
        _viewMatrix = frame.camera.transform
        _rgbResolution = frame.camera.imageResolution

        if _entities.isEmpty,
           let scene = ARSessionManager.shared.scene {
            // Create entities
            let materials = [ SimpleMaterial(color: UIColor.purple, roughness: 1.0, isMetallic: false) ]
            for _ in 0..<(_depthHeight*_depthWidth) {
                let anchor = AnchorEntity(world: .zero)
                anchor.isEnabled = false
                let sphere = MeshResource.generateSphere(radius: 0.01)
                let model = ModelEntity(mesh: sphere, materials: materials)
                anchor.addChild(model)
                _entities.append(anchor)

                // Add to scene
                scene.addAnchor(anchor)
            }
        }

        //image = sceneDepth.depthMap.uiImageFromDepth()
        //image = sceneDepth.confidenceMap?.uiImageFromDepth()

        if _occupancy == nil {
            _occupancy = OccupancyMap(width: 20, depth: 20, cellWidth: 0.5, cellDepth: 0.5, centerPoint: frame.camera.transform.position.xzProjected)
        }

        // First, count the number of observed LiDAR points found in each cell
        let occupancy = _occupancy!
        guard let depthMap = sceneDepth.depthMap.resize(newWidth: 32, newHeight: 24) else { return }
        let observations = OccupancyMap(
            width: occupancy.width,
            depth: occupancy.depth,
            cellWidth: occupancy.cellWidth,
            cellDepth: occupancy.cellDepth,
            centerPoint: occupancy.centerPoint
        )
        observations.updateObservations(
            depthMap: depthMap,
            intrinsics: _intrinsics!,
            rgbResolution: _rgbResolution!,
            viewMatrix: _viewMatrix!,
            floorY: ARSessionManager.shared.floorY
        )

        // Then, update the occupancy map only if the count exceeds a threshold
        occupancy.updateOccupancyFromObservations(from: observations, observationThreshold: 10)

        image = occupancy.render()
    }
}

fileprivate func log(_ message: String) {
    print("[DepthTest] \(message)")
}
