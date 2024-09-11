//
//  GPUOccupancyMap.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
//

import Metal
import simd


// MARK: - Swift Setup and Execution

class GPUOccupancyMap {
    private let _centerPosition: Vector3
    private let _cellWidth: Float
    private let _cellDepth: Float
    private let _cellsWide: Int
    private let _cellsDeep: Int
    private let _device: MTLDevice
    private var _texture: MTLTexture!
    private let _commandQueue: MTLCommandQueue
    private let _pipelineState: MTLComputePipelineState

    var cellWidth: Float {
        return _cellWidth
    }

    var cellDepth: Float {
        return _cellDepth
    }

    var cellsWide: Int {
        return _cellsWide
    }

    var cellsDeep: Int {
        return _cellsDeep
    }

    init(width: Float, depth: Float, cellWidth: Float, cellDepth: Float, centerPosition: Vector3) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create Metal device")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }

        _centerPosition = centerPosition
        _cellWidth = cellWidth
        _cellDepth = cellDepth
        _device = device
        _commandQueue = commandQueue

        // Create compute pipeline
        guard let computeFunction = device.makeDefaultLibrary()?.makeFunction(name: "processVerticesAndUpdateHeightmap") else {
            fatalError("Failed to create compute function")
        }

        do {
            self._pipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }

        // Create texture (grid)
        _cellsWide = Int(floor(width / cellWidth))
        _cellsDeep = Int(floor(depth / cellDepth))
        guard let texture = createTexture(width: _cellsWide, height: _cellsDeep, initialData: Array(repeating: Float(0), count: _cellsWide * _cellsDeep)) else {
            fatalError("Unable to create texture of size \(_cellsWide)x\(_cellsDeep)")
        }
        _texture = texture

        log("Created height map of \(_cellsWide)x\(_cellsDeep) cells")
    }

    func reset(withValues values: [Float]? = nil) {
        let bytesPerRow = _cellsWide * MemoryLayout<Float>.size
        let region = MTLRegionMake2D(0, 0, _cellsWide, _cellsDeep)

        if let values = values {
            guard values.count == _cellsWide * _cellsDeep else {
                print("Error: Provided array size doesn't match map dimensions")
                return
            }
            _texture.replace(region: region, mipmapLevel: 0, withBytes: values, bytesPerRow: bytesPerRow)
        } else {
            // Clear texture to 0
            let zeroBuffer = [Float](repeating: 0, count: _cellsWide * _cellsDeep)
            _texture.replace(region: region, mipmapLevel: 0, withBytes: zeroBuffer, bytesPerRow: bytesPerRow)
        }
    }

    func update(vertices: [Vector3], transforms: [Matrix4x4], transformIndices: [UInt32]) {
        guard vertices.count > 0, transforms.count > 0, transformIndices.count > 0 else {
            return
        }

        guard vertices.count == transformIndices.count else {
            log("Error: Vertex and transform index arrays must be the same length")
            return
        }

        guard let commandBuffer = _commandQueue.makeCommandBuffer() else {
            log("Error: Failed to create command buffer")
            return
        }
              
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            log("Error: Failed to create compute encoder")
            return
        }

        // Set up buffers
        let vertexBuffer = _device.makeBuffer(bytes: vertices, length: MemoryLayout<Vector3>.stride * vertices.count, options: [])
        let matricesBuffer = _device.makeBuffer(bytes: transforms, length: MemoryLayout<simd_float4x4>.stride * transforms.count, options: [])
        let matrixIndicesBuffer = _device.makeBuffer(bytes: transformIndices, length: MemoryLayout<UInt32>.stride * transformIndices.count, options: [])
        let centerPositionBuffer = _device.makeBuffer(bytes: [_centerPosition], length: MemoryLayout<Vector3>.size, options: [])
        let cellsWideBuffer = _device.makeBuffer(bytes: [UInt32(_texture.width)], length: MemoryLayout<UInt32>.size, options: [])
        let cellsDeepBuffer = _device.makeBuffer(bytes: [UInt32(_texture.height)], length: MemoryLayout<UInt32>.size, options: [])
        let cellWidthBuffer = _device.makeBuffer(bytes: [_cellWidth], length: MemoryLayout<Float>.size, options: [])
        let cellDepthBuffer = _device.makeBuffer(bytes: [_cellDepth], length: MemoryLayout<Float>.size, options: [])

        computeEncoder.setComputePipelineState(_pipelineState)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setTexture(_texture, index: 0)
        computeEncoder.setBuffer(matricesBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(matrixIndicesBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(centerPositionBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(cellsWideBuffer, offset: 0, index: 4)
        computeEncoder.setBuffer(cellsDeepBuffer, offset: 0, index: 5)
        computeEncoder.setBuffer(cellWidthBuffer, offset: 0, index: 6)
        computeEncoder.setBuffer(cellDepthBuffer, offset: 0, index: 7)

        let gridSize = MTLSize(width: vertices.count, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: _pipelineState.threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)

        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func getMapArray() -> [Float]? {
        let width = _texture.width
        let height = _texture.height
        let bytesPerRow = width * MemoryLayout<Float>.size
        let dataSize = height * bytesPerRow

        guard let buffer = _device.makeBuffer(length: dataSize, options: .storageModeShared) else {
            print("Failed to create buffer")
            return nil
        }

        guard let blitCommandBuffer = _commandQueue.makeCommandBuffer(),
              let blitCommandEncoder = blitCommandBuffer.makeBlitCommandEncoder() else {
            print("Failed to create blit command buffer or encoder")
            return nil
        }

        blitCommandEncoder.copy(
            from: _texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: dataSize
        )

        blitCommandEncoder.endEncoding()
        blitCommandBuffer.commit()
        blitCommandBuffer.waitUntilCompleted()

        let data = buffer.contents().bindMemory(to: Float.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: data, count: width * height))
    }

    func linearIndex(cellX: Int, cellZ: Int) -> Int {
        // Textures are stored row by row and the width dimension is cellsWide
        return cellZ * cellsWide + cellX
    }

    func centerCell() -> (cellX: Int, cellZ: Int) {
        return (cellX: Int(round(Float(cellsWide) * 0.5)), cellZ: Int(round(Float(cellsDeep) * 0.5)))
    }

    /// Given a world space position (x, y, z), finds the height map cell indices. Coordinates
    /// outside the map boundaries are clamped to the outer cells.
    /// - Parameter position: World position.
    /// - Returns: The integral x and z cell indices of the cell containing the world point or, if
    /// the coordinate is out of bounds, the nearest cell on the perimeter.
    func positionToIndices(position: Vector3) -> (cellX: Int, cellZ: Int) {
        let centerCell = centerCell()
        var xi = Int(floor((position.x - _centerPosition.x) / cellWidth + 0.5)) + centerCell.cellX
        var zi = Int(floor((position.z - _centerPosition.z) / cellDepth + 0.5)) + centerCell.cellZ
        xi = min(max(0, xi), cellsWide - 1)
        zi = min(max(0, zi), cellsDeep - 1)
        return (cellX: xi, cellZ: zi)
    }

    /// Given a world space position (x, y, z), finds the height map cell indices as floats. These
    /// may be fractional (e.g., (1.05, 23.42)). Cell coordinates are clamped between -0.5 and
    /// (numCells - 1 + 0.5) along each axis.
    /// - Parameter position: World position.
    /// - Returns: The decimal x and z cell indices
    func positionToFractionalIndices(position: Vector3) -> (cellX: Float, cellZ: Float) {
        let centerCell = centerCell()
        var xf = ((position.x - _centerPosition.x) / cellWidth) + Float(centerCell.cellX)
        var zf = ((position.z - _centerPosition.z) / cellDepth) + Float(centerCell.cellZ)

        // Clamp to edges. Note that the only difference between this function and positionToIndices()
        // is that the latter adds 0.5 and then floors. Therefore, we know the limits are: [-0.5, s_numCells - 1 + 0.5).
        xf = min(max(-0.5, xf), Float(cellsWide - 1) + 0.5)
        zf = min(max(-0.5, zf), Float(cellsDeep - 1) + 0.5)
        return (cellX: xf, cellZ: zf)
    }

    private func createTexture(width: Int, height: Int, initialData: [Float]? = nil) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .shared

        guard let texture = _device.makeTexture(descriptor: textureDescriptor) else {
            log("Error: Failed to create texture")
            return nil
        }

        if let data = initialData {
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: width * MemoryLayout<Float>.size)
        }

        return texture
    }
}

fileprivate func log(_ message: String) {
    print("[GPUOccupancyMap] \(message)")
}
