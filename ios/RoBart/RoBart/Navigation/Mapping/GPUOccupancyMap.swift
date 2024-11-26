//
//  GPUOccupancyMap.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/10/24.
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

import Metal
import simd

class GPUOccupancyMap {
    private let _device: MTLDevice
    private var _texture: MTLTexture!
    private let _commandQueue: MTLCommandQueue
    private let _pipelineState: MTLComputePipelineState

    /// Width of map (x axis) in meters.
    private(set) var width: Float

    /// Depth of map (z axis) in meters.
    private(set) var depth: Float

    /// Side length of a map cell in meters.
    private(set) var cellSide: Float

    /// Width of the map in integral cell units.
    private(set) var cellsWide: Int

    /// Depth of the map in integral cell units.
    private(set) var cellsDeep: Int

    /// Center point of the map in world coordinates.
    private(set) var centerPoint: Vector3

    init(width: Float, depth: Float, cellSide: Float, centerPoint: Vector3) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create Metal device")
        }

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }

        _device = device
        _commandQueue = commandQueue
        self.width = width
        self.depth = depth
        self.cellSide = cellSide
        self.centerPoint = centerPoint

        // Create compute pipeline
        guard let computeFunction = device.makeDefaultLibrary()?.makeFunction(name: "processVerticesAndUpdateOccupancy") else {
            fatalError("Failed to create compute function")
        }

        do {
            self._pipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }

        // Create texture (grid)
        cellsWide = Int(floor(width / cellSide))
        cellsDeep = Int(floor(depth / cellSide))
        guard let texture = createTexture(width: cellsWide, height: cellsDeep, initialData: Array(repeating: Float(0), count: cellsWide * cellsDeep)) else {
            fatalError("Unable to create texture of size \(cellsWide)x\(cellsDeep)")
        }
        _texture = texture

        log("Created height map of \(cellsWide)x\(cellsDeep) cells")
    }

    func reset(to initialValue: Float) {
        let bytesPerRow = cellsWide * MemoryLayout<Float>.size
        let region = MTLRegionMake2D(0, 0, cellsWide, cellsDeep)
        let zeroBuffer = [Float](repeating: initialValue, count: cellsWide * cellsDeep)
        _texture.replace(region: region, mipmapLevel: 0, withBytes: zeroBuffer, bytesPerRow: bytesPerRow)
    }

    func reset(withValues values: [Float]? = nil) {
        let bytesPerRow = cellsWide * MemoryLayout<Float>.size
        let region = MTLRegionMake2D(0, 0, cellsWide, cellsDeep)

        if let values = values {
            guard values.count == cellsWide * cellsDeep else {
                print("Error: Provided array size doesn't match map dimensions")
                return
            }
            _texture.replace(region: region, mipmapLevel: 0, withBytes: values, bytesPerRow: bytesPerRow)
        } else {
            // Clear texture to 0
            let zeroBuffer = [Float](repeating: 0, count: cellsWide * cellsDeep)
            _texture.replace(region: region, mipmapLevel: 0, withBytes: zeroBuffer, bytesPerRow: bytesPerRow)
        }
    }

    /// Updates the occupancy map with the given vertex data. Does not clear the map beforehand.
    /// - Parameter vertices: Vertices to process.
    /// - Parameter transforms: Local-to-world transform matrices.
    /// - Parameter transformIndices: For each vertex, an index into `transforms` for the transform matrix to apply to that vertex.
    /// - Parameter minOccupiedHeight: The minimum world-space Y value to mark a cell as occupied. If any vertex's world-space Y value
    /// is in the range [ `minOccupiedHeight`, `maxOccupiedHeight` ], its corresponding map cell will be marked as occupied (1.0).
    /// - Parameter maxOccupiedHeight: The maximum world-space Y value to mark a cell as occupied.
    /// - Parameter completion: An optional completion to run on the main queue when the GPU has finished. If this is `nil`,
    /// the function blocks. When using this, the caller is responsible for ensuring `update` is not called again until after the completion finishes.
    /// - Returns: `true` if successful and the completion will be called, otherwise `false` if an error occurred and the completion will not be
    /// invoked.
    func update(
        vertices: [Vector3],
        transforms: [Matrix4x4],
        transformIndices: [UInt32],
        minOccupiedHeight: Float,
        maxOccupiedHeight: Float,
        completion: ((MTLCommandBuffer) -> Void)? = nil
    ) -> Bool {
        guard vertices.count > 0, transforms.count > 0, transformIndices.count > 0 else {
            return false
        }

        guard vertices.count == transformIndices.count else {
            log("Error: Vertex and transform index arrays must be the same length")
            return false
        }

        guard let commandBuffer = _commandQueue.makeCommandBuffer() else {
            log("Error: Failed to create command buffer")
            return false
        }

        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            log("Error: Failed to create compute encoder")
            return false
        }

        // Set up buffers
        let vertexBuffer = _device.makeBuffer(bytes: vertices, length: MemoryLayout<Vector3>.stride * vertices.count, options: [])
        let matricesBuffer = _device.makeBuffer(bytes: transforms, length: MemoryLayout<simd_float4x4>.stride * transforms.count, options: [])
        let matrixIndicesBuffer = _device.makeBuffer(bytes: transformIndices, length: MemoryLayout<UInt32>.stride * transformIndices.count, options: [])
        let centerPositionBuffer = _device.makeBuffer(bytes: [centerPoint], length: MemoryLayout<Vector3>.size, options: [])
        let cellsWideBuffer = _device.makeBuffer(bytes: [UInt32(_texture.width)], length: MemoryLayout<UInt32>.size, options: [])
        let cellsDeepBuffer = _device.makeBuffer(bytes: [UInt32(_texture.height)], length: MemoryLayout<UInt32>.size, options: [])
        let cellSideBuffer = _device.makeBuffer(bytes: [cellSide], length: MemoryLayout<Float>.size, options: [])
        let minHeightBuffer = _device.makeBuffer(bytes: [minOccupiedHeight], length: MemoryLayout<Float>.size, options: [])
        let maxHeightBuffer = _device.makeBuffer(bytes: [maxOccupiedHeight], length: MemoryLayout<Float>.size, options: [])

        computeEncoder.setComputePipelineState(_pipelineState)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setTexture(_texture, index: 0)
        computeEncoder.setBuffer(matricesBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(matrixIndicesBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(centerPositionBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(cellsWideBuffer, offset: 0, index: 4)
        computeEncoder.setBuffer(cellsDeepBuffer, offset: 0, index: 5)
        computeEncoder.setBuffer(cellSideBuffer, offset: 0, index: 6)
        computeEncoder.setBuffer(minHeightBuffer, offset: 0, index: 7)
        computeEncoder.setBuffer(maxHeightBuffer, offset: 0, index: 8)

        // Map vertices to threads. Note that this creates a potential race condition accessing the
        // texture, as multiple vertices in different threads may map to the same texel.
        let gridSize = MTLSize(width: vertices.count, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: _pipelineState.threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)

        computeEncoder.endEncoding()
        if let completion = completion {
            commandBuffer.addCompletedHandler({ (commandBuffer: MTLCommandBuffer) in
                DispatchQueue.main.async { completion(commandBuffer) }
            })
            commandBuffer.commit()
        } else {
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }

        return true
    }

    func update(
        vertices: [Vector3],
        transforms: [Matrix4x4],
        transformIndices: [UInt32],
        minOccupiedHeight: Float,
        maxOccupiedHeight: Float
    ) async -> MTLCommandBuffer? {
        let stream = AsyncStream<MTLCommandBuffer> { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            let succeeded = update(
                vertices: vertices,
                transforms: transforms,
                transformIndices: transformIndices,
                minOccupiedHeight: minOccupiedHeight,
                maxOccupiedHeight: maxOccupiedHeight
            ) { (commandBuffer: MTLCommandBuffer) in
                continuation.yield(commandBuffer)
                continuation.finish()
            }
            if !succeeded {
                continuation.finish()
            }
        }

        // Only care about first event
        var it = stream.makeAsyncIterator()
        return await it.next()
    }

    /// Obtains the map by copying it from GPU to CPU.
    /// - Returns: A linear array of floating point values having size `cellsWide * cellsDeep` or `nil`
    /// if the underlying texture could not be retrieved from the GPU.
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

    /// Given a world space position (x, y, z), finds the occupancy map cell indices. Coordinates
    /// outside the map boundaries are clamped to the outer cells.
    /// - Parameter position: World position.
    /// - Returns: The integral x and z cell indices of the cell containing the world point or, if
    /// the coordinate is out of bounds, the nearest cell on the perimeter.
    func positionToIndices(position: Vector3) -> (cellX: Int, cellZ: Int) {
        let centerCell = centerCell()
        var xi = Int(floor((position.x - centerPoint.x) / cellSide + 0.5)) + centerCell.cellX
        var zi = Int(floor((position.z - centerPoint.z) / cellSide + 0.5)) + centerCell.cellZ
        xi = min(max(0, xi), cellsWide - 1)
        zi = min(max(0, zi), cellsDeep - 1)
        return (cellX: xi, cellZ: zi)
    }

    /// Given a world space position (x, y, z), finds the occupancy map cell indices as floats. These
    /// may be fractional (e.g., (1.05, 23.42)). Cell coordinates are clamped between -0.5 and
    /// (numCells - 1 + 0.5) along each axis.
    /// - Parameter position: World position.
    /// - Returns: The decimal x and z cell indices
    func positionToFractionalIndices(position: Vector3) -> (cellX: Float, cellZ: Float) {
        let centerCell = centerCell()
        var xf = ((position.x - centerPoint.x) / cellSide) + Float(centerCell.cellX)
        var zf = ((position.z - centerPoint.z) / cellSide) + Float(centerCell.cellZ)

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
