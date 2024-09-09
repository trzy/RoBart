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

    private var _cOccupancy: COccupancyMap?
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

        if _cOccupancy == nil {
            _cOccupancy = COccupancyMap(
                20,     // width
                20,     // depth
                0.5,    // cellWidth
                0.5,    // cellDepth
                frame.camera.transform.position.xzProjected // centerPoint
            )

            _occupancy = OccupancyMap(width: 20, depth: 20, cellWidth: 0.5, cellDepth: 0.5, centerPoint: frame.camera.transform.position.xzProjected)
        }

//        if let f = sceneDepth.confidenceMap?.toUInt8Array() {
//            for i in 0..<f.count {
//                print("\(i)=\(f[i])")
//            }
//            fatalError("foo")
//        }

        guard let confidenceMap = sceneDepth.confidenceMap else { return }

        // Filter out low confidence depth values
        filterDepthMap(sceneDepth.depthMap, confidenceMap, UInt8(ARConfidenceLevel.medium.rawValue))

        // Resize depth map to be smaller
        guard let depthMap = sceneDepth.depthMap.resize(newWidth: 32, newHeight: 24) else { return }

        // Swift version
        var occupancy = _occupancy!
        guard let depthMap = sceneDepth.depthMap.resize(newWidth: 32, newHeight: 24) else { return }
        var observations = OccupancyMap(width: occupancy.width, depth: occupancy.depth, cellWidth: occupancy.cellWidth, cellDepth: occupancy.cellDepth, centerPoint: occupancy.centerPoint)
        observations.updateObservations(depthMap: depthMap, intrinsics: _intrinsics!, rgbResolution: _rgbResolution!, viewMatrix: _viewMatrix!, floorY: ARSessionManager.shared.floorY)
        occupancy.updateOccupancyFromObservations(from: observations, observationThreshold: 10)
        //image = occupancy.render()


        // First, count the number of observed LiDAR points found in each cell
        var cOccupancy = _cOccupancy!
        var cObservations = COccupancyMap(
            cOccupancy.width(),
            cOccupancy.depth(),
            cOccupancy.cellWidth(),
            cOccupancy.cellDepth(),
            cOccupancy.centerPoint()
        )
        cObservations.updateObservationCounts(
            depthMap,
            _intrinsics!,
            simd_float2(Float(_rgbResolution!.width), Float(_rgbResolution!.height)),
            _viewMatrix!,
            ARSessionManager.shared.floorY,
            Calibration.phoneHeight
        )

        // Then, update the occupancy map only if the count exceeds a threshold
        cOccupancy.updateOccupancyFromObservationCounts(cObservations, 10)

        image = renderOccupancy(occupancy: cOccupancy)
    }

    private func suppressLowConfidenceDepthValues(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer, minimumConfidence: ARConfidenceLevel) {
        assert(depthMap.format == kCVPixelFormatType_DepthFloat32)
        assert(confidenceMap.format == kCVPixelFormatType_OneComponent8)
        assert(depthMap.width == confidenceMap.width)
        assert(depthMap.height == confidenceMap.height)

        let width = depthMap.width
        let height = depthMap.height

        CVPixelBufferLockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        let offsetToNextLineDepthMap = (depthMap.bytesPerRow / MemoryLayout<Float>.stride) - depthMap.width
        let offsetToNextLineConfidenceMap = confidenceMap.bytesPerRow - confidenceMap.width

        if let depthMapAddress = CVPixelBufferGetBaseAddress(depthMap),
           let confidenceMapAddress = CVPixelBufferGetBaseAddress(confidenceMap) {
            let depthFloats = depthMapAddress.assumingMemoryBound(to: Float.self)
            let confidenceBytes = confidenceMapAddress.assumingMemoryBound(to: UInt8.self)

            // Preserve only high confidence depth values. Low confidence values set to infinity.
            var depthIdx = 0
            var confidenceIdx = 0
            for _ in 0..<height {
                for _ in 0..<width {
                    if confidenceBytes[confidenceIdx] < minimumConfidence.rawValue {
                        depthFloats[depthIdx] = 1e6
                    }
                    depthIdx += 1
                    confidenceIdx += 1
                }
                depthIdx += offsetToNextLineDepthMap
                confidenceIdx += offsetToNextLineConfidenceMap
            }
        }

        CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        CVPixelBufferUnlockBaseAddress(depthMap, CVPixelBufferLockFlags(rawValue: 0))
    }

    private func renderOccupancy(occupancy map: COccupancyMap) -> UIImage? {
        let pixLength = 10
        let imageSize = CGSize(width: map.cellsWide() * pixLength, height: map.cellsDeep() * pixLength)

        // Create a graphics context to draw the image
        UIGraphicsBeginImageContext(imageSize)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Loop through the occupancy grid and draw squares
        for zi in 0..<map.cellsDeep() {
            for xi in 0..<map.cellsWide() {
                let isOccupied = map.at(xi, zi) > 0

                // Set the color based on occupancy
                let color: UIColor = isOccupied ? .blue : .white
                context.setFillColor(color.cgColor)

                // Define the square's rectangle
                let rect = CGRect(x: xi * pixLength, y: zi * pixLength, width: pixLength, height: pixLength)

                // Draw the rectangle
                context.fill(rect)
            }
        }

        // Draw circle at our current position
        let ourCell = map.positionToIndices(ARSessionManager.shared.transform.position)
        let ourCellX = CGFloat(ourCell.first)
        let ourCellY = CGFloat(ourCell.second)
        let ourPosX = (ourCellX + 0.5) * CGFloat(pixLength)
        let ourPosY = (ourCellY + 0.5) * CGFloat(pixLength)
        context.setFillColor(UIColor.red.cgColor)
        let center = CGPoint(x: ourPosX, y: ourPosY)
        let path = UIBezierPath(
            arcCenter: center,
            radius: 0.5 * CGFloat(pixLength),
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
        path.fill()

        // Draw a little arc in front of our current heading
        let inFront = ARSessionManager.shared.transform.position - 1.0 * ARSessionManager.shared.transform.forward.xzProjected
        let cellInFront = map.positionToFractionalIndices(inFront)
        let posFarInFront = simd_float2((Float(cellInFront.first) + 0.5 ) * Float(pixLength), (Float(cellInFront.second) + 0.5 ) * Float(pixLength))
        let posCenter = simd_float2(Float(ourPosX), Float(ourPosY))
        let forwardDir = simd_normalize(posFarInFront - posCenter)
        let linePath = UIBezierPath()
        linePath.move(to: center)
        linePath.addLine(to: CGPoint(x: center.x + CGFloat(forwardDir.x) * CGFloat(2 * pixLength), y: center.y + CGFloat(forwardDir.y) * CGFloat(2 * pixLength)))
        context.setStrokeColor(UIColor.red.cgColor)
        linePath.stroke()
        
        // Retrieve the generated image
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }
}

fileprivate func log(_ message: String) {
    print("[DepthTest] \(message)")
}
