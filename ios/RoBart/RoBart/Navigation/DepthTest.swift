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

    /// How often we sample the depth map and accumulate cell hit counts.
    private let _targetDepthSampleRateHz: Double = 10

    /// How often we commit updates to the occupancy map itself.
    private let _targetOccupancyUpdateRateHz: Double = 1

    /// The last frame timestamp at which we sampled depth.
    private var _lastDepthSampleTimestamp: TimeInterval?

    /// THe last frame timestamp at which we updated the occupancy map.
    private var _lastOccupancyUpdateTimestamp: TimeInterval?

    /// Moving average of LiDAR samples found in each cell.
    private var _hitCounts: OccupancyMap?

    /// Occupancy map (binary occupied/not occupied), integrated from hit count map or from GPU
    /// occupancy map.
    private var _occupancy: OccupancyMap?

    /// Occupancy map computed from scene mesh vertices on GPU.
    private var _gpuOccupancy: GPUOccpancyMap?

    init() {
        assert(_targetDepthSampleRateHz >= _targetOccupancyUpdateRateHz)
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

    func testPath() {
        var timer = Util.Stopwatch()
        timer.start()

        // Lazy instantiate occupancy map on first frame, when we have our initial position
        if _gpuOccupancy == nil {
            _gpuOccupancy = GPUOccpancyMap(
                width: 20,
                depth: 20,
                cellWidth: 0.5,
                cellDepth: 0.5,
                centerPoint: ARSessionManager.shared.transform.position
            )

            _occupancy = OccupancyMap(
                _gpuOccupancy!.width,
                _gpuOccupancy!.depth,
                _gpuOccupancy!.cellWidth,
                _gpuOccupancy!.cellDepth,
                _gpuOccupancy!.centerPoint
            )
        }
        let gpuOccupancy = _gpuOccupancy!

        // Unbundle all meshes into a linear array of vertices and associate a transform with each
        var vertices: [Vector3] = []
        var transforms: [Matrix4x4] = []
        var transformIdxs: [UInt32] = []
        let meshes = ARSessionManager.shared.sceneMeshes
        var transformIdx: UInt32 = 0
        for mesh in meshes {
            transforms.append(mesh.transform)
            for vertex in mesh.vertices {
                vertices.append(vertex)
                transformIdxs.append(transformIdx)
            }
            transformIdx += 1
        }

        // Update GPU occupancy map
        let minHeight = ARSessionManager.shared.floorY + 0.25
        let maxHeight = ARSessionManager.shared.floorY + Calibration.phoneHeightAboveFloor
        gpuOccupancy.reset(to: 0)
        _ = gpuOccupancy.update(
            vertices: vertices,
            transforms: transforms,
            transformIndices: transformIdxs,
            minOccupiedHeight: minHeight,
            maxOccupiedHeight: maxHeight
        ) { [weak self] (commandBuffer: MTLCommandBuffer) in
            guard let self = self else { return }

            // Update occupancy map from GPU map
            var occupancy = _occupancy!
            if let occupancyArray = gpuOccupancy.getMapArray() {
                occupancyArray.withUnsafeBufferPointer { ptr in
                    occupancy.updateOccupancyFromArray(ptr.baseAddress, occupancyArray.count)
                }
            }

            log("Occupancy updated: \(timer.elapsedMilliseconds()) ms")

            // Path
            let from = ARSessionManager.shared.transform.position;
            let to = occupancy.centerPoint()
            let pathCells = findPath(occupancy, from, to)
            image = renderOccupancy(occupancy: occupancy, path: pathCells.map { $0 })
        }


//        guard let occupancy = _occupancy else { return }
//        let from = ARSessionManager.shared.transform.position;
//        let to = occupancy.centerPoint()
//        let path = findPath(occupancy, from, to)
//        var pathCells: [(cellX: Int, cellZ: Int)] = []
//        for cell in path {
//            pathCells.append((cellX: Int(cell.first), cellZ: Int(cell.second)))
//        }
//        image = renderOccupancy(occupancy: occupancy, path: pathCells)
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

        // Update occupancy using scene depth
        //updateOccupancyUsingSceneDepth(frame: frame)

        // Update occupancy using scene meshes
        //updateOccupancyUsingSceneGeometry(frame: frame)
    }

    private func updateOccupancyUsingSceneGeometry(frame: ARFrame) {
        // Is it time to update the actual occupancy map?
        guard let lastOccupancyUpdateTimestamp = _lastOccupancyUpdateTimestamp else {
            _lastOccupancyUpdateTimestamp = frame.timestamp
            return
        }
        let nextOccupancyUpdateTime = lastOccupancyUpdateTimestamp + (1.0 / _targetOccupancyUpdateRateHz)
        guard frame.timestamp >= nextOccupancyUpdateTime else { return }
        _lastOccupancyUpdateTimestamp = frame.timestamp

        var timer = Util.Stopwatch()
        timer.start()

        // Lazy instantiate occupancy map on first frame, when we have our initial position
        if _gpuOccupancy == nil {
            _gpuOccupancy = GPUOccpancyMap(
                width: 20,
                depth: 20,
                cellWidth: 0.5,
                cellDepth: 0.5,
                centerPoint: ARSessionManager.shared.transform.position
            )

            _occupancy = OccupancyMap(
                _gpuOccupancy!.width,
                _gpuOccupancy!.depth,
                _gpuOccupancy!.cellWidth,
                _gpuOccupancy!.cellDepth,
                _gpuOccupancy!.centerPoint
            )
        }
        let gpuOccupancy = _gpuOccupancy!

        // Unbundle all meshes into a linear array of vertices and associate a transform with each
        var vertices: [Vector3] = []
        var transforms: [Matrix4x4] = []
        var transformIdxs: [UInt32] = []
        let meshes = ARSessionManager.shared.sceneMeshes
        var transformIdx: UInt32 = 0
        for mesh in meshes {
            transforms.append(mesh.transform)
            for vertex in mesh.vertices {
                vertices.append(vertex)
                transformIdxs.append(transformIdx)
            }
            transformIdx += 1
        }

        // Update height map
        let minHeight = ARSessionManager.shared.floorY + 0.25
        let maxHeight = ARSessionManager.shared.floorY + Calibration.phoneHeightAboveFloor
        gpuOccupancy.reset(to: 0)
        gpuOccupancy.update(
            vertices: vertices,
            transforms: transforms,
            transformIndices: transformIdxs,
            minOccupiedHeight: minHeight,
            maxOccupiedHeight: maxHeight
        )

        // Update occupancy map from height map
        var occupancy = _occupancy!
        if let occupancyArray = gpuOccupancy.getMapArray() {
            occupancyArray.withUnsafeBufferPointer { ptr in
                occupancy.updateOccupancyFromArray(ptr.baseAddress, occupancyArray.count)
            }
        }

        log("Occupancy updated: \(timer.elapsedMilliseconds()) ms")

        image = renderOccupancy(occupancy: occupancy)
    }

    private func updateOccupancyUsingSceneDepth(frame: ARFrame) {
        guard let sceneDepth = _sceneDepth,
              let intrinsics = _intrinsics,
              let viewMatrix = _viewMatrix,
              let rgbResolution = _rgbResolution else {
            return
        }

        // Is it time to sample depth and update cell hit counts?
        guard let lastDepthSampleTimestamp = _lastDepthSampleTimestamp else {
            _lastDepthSampleTimestamp = frame.timestamp
            return
        }
        let nextDepthSampleTime = lastDepthSampleTimestamp + (1.0 / _targetDepthSampleRateHz)
        guard frame.timestamp >= nextDepthSampleTime else { return }
        let sampleDeltaTime = frame.timestamp - lastDepthSampleTimestamp
        _lastDepthSampleTimestamp = frame.timestamp

        // Lazy instantiate occupancy map on first frame
        var timer = Util.Stopwatch()
        timer.start()
        if _occupancy == nil {
            _hitCounts = OccupancyMap(
                20,     // width (meters)
                20,     // depth (meters)
                0.5,    // cell width (meters)
                0.5,    // cell depth (meters)
                frame.camera.transform.position.xzProjected // world center point
            )
            _occupancy = OccupancyMap(
                _hitCounts!.width(),
                _hitCounts!.depth(),
                _hitCounts!.cellWidth(),
                _hitCounts!.cellDepth(),
                _hitCounts!.centerPoint()
            )
        }

        var hitCounts = _hitCounts!
        var occupancy = _occupancy!

        // Filter out low confidence depth values
        guard let confidenceMap = sceneDepth.confidenceMap else { return }
        let depthMap = sceneDepth.depthMap
        filterDepthMap(depthMap, confidenceMap, UInt8(ARConfidenceLevel.high.rawValue))

        // Update expontential moving average of the number of LiDAR points in each cell
        let minDepth: Float = 1.0
        let maxDepth: Float = 3.0
        let minHeight = ARSessionManager.shared.floorY + 0.25
        let maxHeight = ARSessionManager.shared.floorY + Calibration.phoneHeightAboveFloor
        let tau: Float = 1.0
        let newSampleWeight: Float = 1.0 - exp(-Float(sampleDeltaTime) / tau)   // EWMA: https://en.wikipedia.org/wiki/Exponential_smoothing
        let previousWeight: Float = 1.0 - newSampleWeight
        hitCounts.updateCellCounts(
            depthMap,
            intrinsics,
            simd_float2(Float(rgbResolution.width), Float(rgbResolution.height)),
            viewMatrix,
            minDepth,
            maxDepth,
            minHeight,
            maxHeight,
            newSampleWeight,
            previousWeight
        )

        //log("Depth sample update: \(timer.elapsedMilliseconds()) ms")
        //log("Sample rate: \(1.0/sampleDeltaTime) Hz")

        // Is it time to update the actual occupancy map?
        guard let lastOccupancyUpdateTimestamp = _lastOccupancyUpdateTimestamp else {
            _lastOccupancyUpdateTimestamp = frame.timestamp
            return
        }
        let nextOccupancyUpdateTime = lastOccupancyUpdateTimestamp + (1.0 / _targetOccupancyUpdateRateHz)
        guard frame.timestamp >= nextOccupancyUpdateTime else { return }
        _lastOccupancyUpdateTimestamp = frame.timestamp

        // Then, update the occupancy map only if the count exceeds a threshold
        occupancy.updateOccupancyFromCounts(
            hitCounts,
            10  // count threshold
        )

        //log("Occupancy update: \(timer.elapsedMilliseconds()) ms")
        //log("Update rate: \(1.0/(frame.timestamp - lastOccupancyUpdateTimestamp)) Hz")

        image = renderOccupancy(occupancy: occupancy)
    }

    private func renderOccupancy(occupancy map: OccupancyMap, path: [OccupancyMap.CellIndices] = []) -> UIImage? {
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

        // Draw path, if one given
        context.setFillColor(UIColor.black.cgColor)
        for cell in path {
            // A slightly smaller rect
            let crumbLength = pixLength / 2
            let rect = CGRect(
                x: cell.cellX * pixLength + (pixLength - crumbLength) / 2,
                y: cell.cellZ * pixLength + (pixLength - crumbLength) / 2,
                width: crumbLength,
                height: crumbLength
            )
            context.fill(rect)
        }

        // Draw circle at our current position
        let ourCell = map.positionToCell(ARSessionManager.shared.transform.position)
        let ourCellX = CGFloat(ourCell.cellX)
        let ourCellZ = CGFloat(ourCell.cellZ)
        let ourPosX = (ourCellX + 0.5) * CGFloat(pixLength)
        let ourPosZ = (ourCellZ + 0.5) * CGFloat(pixLength)
        context.setFillColor(UIColor.red.cgColor)
        let center = CGPoint(x: ourPosX, y: ourPosZ)
        let path = UIBezierPath(
            arcCenter: center,
            radius: 0.5 * CGFloat(pixLength),
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
        path.fill()

        // Draw a little line in front of our current heading
        let inFront = ARSessionManager.shared.transform.position - 1.0 * ARSessionManager.shared.transform.forward.xzProjected
        let cellInFront = map.positionToFractionalIndices(inFront)
        let posFarInFront = simd_float2((cellInFront.cellX + 0.5 ) * Float(pixLength), (cellInFront.cellZ + 0.5 ) * Float(pixLength))
        let posCenter = simd_float2(Float(ourPosX), Float(ourPosZ))
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

    private func renderOccupancy(occupancy map: GPUOccpancyMap, path: [(cellX: Int, cellZ: Int)] = []) -> UIImage? {
        // Get data
        guard let data = map.getMapArray() else { return nil }

        // Map dimensions
        let pixLength = 10
        let imageSize = CGSize(width: map.cellsWide * pixLength, height: map.cellsDeep * pixLength)

        // Create a graphics context to draw the image
        UIGraphicsBeginImageContext(imageSize)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Loop through the occupancy grid and draw squares
        for zi in 0..<map.cellsDeep {
            for xi in 0..<map.cellsWide {
                let idx = map.linearIndex(cellX: xi, cellZ: zi)
                let isOccupied = data[idx] > 0

                // Set the color based on occupancy
                let color: UIColor = isOccupied ? .blue : .white
                context.setFillColor(color.cgColor)

                // Define the square's rectangle
                let rect = CGRect(x: xi * pixLength, y: zi * pixLength, width: pixLength, height: pixLength)

                // Draw the rectangle
                context.fill(rect)
            }
        }

        // Draw path, if one given
        context.setFillColor(UIColor.black.cgColor)
        for cell in path {
            // A slightly smaller rect
            let crumbLength = pixLength / 2
            let rect = CGRect(
                x: cell.cellX * pixLength + (pixLength - crumbLength) / 2,
                y: cell.cellZ * pixLength + (pixLength - crumbLength) / 2,
                width: crumbLength,
                height: crumbLength
            )
            context.fill(rect)
        }

        // Draw circle at our current position
        let robotPosition = ARSessionManager.shared.transform.position
        let robotForward = -ARSessionManager.shared.transform.forward.xzProjected.normalized
        let ourCell = map.positionToIndices(position: robotPosition)
        let ourCellX = CGFloat(ourCell.cellX)
        let ourCellZ = CGFloat(ourCell.cellZ)
        let ourPosX = (ourCellX + 0.5) * CGFloat(pixLength)
        let ourPosZ = (ourCellZ + 0.5) * CGFloat(pixLength)
        context.setFillColor(UIColor.red.cgColor)
        let center = CGPoint(x: ourPosX, y: ourPosZ)
        let path = UIBezierPath(
            arcCenter: center,
            radius: 0.5 * CGFloat(pixLength),
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
        path.fill()

        // Draw a little line in front of our current heading
        let inFront = robotPosition + 1.0 * robotForward
        let cellInFront = map.positionToFractionalIndices(position: inFront)
        let posFarInFront = simd_float2((Float(cellInFront.cellX) + 0.5) * Float(pixLength), (Float(cellInFront.cellZ) + 0.5 ) * Float(pixLength))
        let posCenter = simd_float2(Float(ourPosX), Float(ourPosZ))
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
