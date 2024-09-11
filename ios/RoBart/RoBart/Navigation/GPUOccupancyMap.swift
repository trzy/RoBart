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
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            print("Unable to create device or command queue")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Create the compute pipeline
//        var library: MTLLibrary!
//        do {
//            library = try device.makeLibrary(source: metalShaderSource, options: nil)
//        } catch {
//            print("Error: \(error)")
//            return nil
//        }
//        guard let computeFunction = library.makeFunction(name: "processVerticesAndUpdateTexture") else {
//            print("Unable to create compute function")
//            return nil
//        }
        guard let computeFunction = device.makeDefaultLibrary()?.makeFunction(name: "processVerticesAndUpdateTexture") else {
            print("Unable to create compute function")
            return nil
        }

        do {
            self.pipelineState = try device.makeComputePipelineState(function: computeFunction)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }
    }

    func processVertices(vertices: [Vector3], texture: MTLTexture, transformMatrix: simd_float4x4) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("Failed to create command buffer or compute encoder")
            return
        }

        // Set up buffers
        let vertexBuffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<simd_float3>.stride * vertices.count, options: [])
        let matrixBuffer = device.makeBuffer(bytes: [transformMatrix], length: MemoryLayout<simd_float4x4>.size, options: [])
        let widthBuffer = device.makeBuffer(bytes: [UInt32(texture.width)], length: MemoryLayout<UInt32>.size, options: [])
        let heightBuffer = device.makeBuffer(bytes: [UInt32(texture.height)], length: MemoryLayout<UInt32>.size, options: [])

        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        computeEncoder.setTexture(texture, index: 0)
        computeEncoder.setBuffer(matrixBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(widthBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(heightBuffer, offset: 0, index: 3)

        let gridSize = MTLSize(width: vertices.count, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: pipelineState.threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)

        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // Add this method to the MeshTextureProcessor class
    func getTextureData(from texture: MTLTexture) -> [Float]? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * MemoryLayout<Float>.size
        let dataSize = height * bytesPerRow

        guard let buffer = device.makeBuffer(length: dataSize, options: .storageModeShared) else {
            print("Failed to create buffer")
            return nil
        }

        guard let blitCommandBuffer = commandQueue.makeCommandBuffer(),
              let blitCommandEncoder = blitCommandBuffer.makeBlitCommandEncoder() else {
            print("Failed to create blit command buffer or encoder")
            return nil
        }

        blitCommandEncoder.copy(from: texture,
                                sourceSlice: 0,
                                sourceLevel: 0,
                                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                                sourceSize: MTLSize(width: width, height: height, depth: 1),
                                to: buffer,
                                destinationOffset: 0,
                                destinationBytesPerRow: bytesPerRow,
                                destinationBytesPerImage: dataSize)

        blitCommandEncoder.endEncoding()
        blitCommandBuffer.commit()
        blitCommandBuffer.waitUntilCompleted()

        let data = buffer.contents().bindMemory(to: Float.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: data, count: width * height))
    }

    func createTexture(width: Int, height: Int, initialData: [Float]? = nil) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            print("Failed to create texture")
            return nil
        }

        if let data = initialData {
            let region = MTLRegionMake2D(0, 0, width, height)
            texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: width * MemoryLayout<Float>.size)
        }

        return texture
    }

    func resetTexture(_ texture: MTLTexture, withValues values: [Float]? = nil) {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * MemoryLayout<Float>.size
        let regionSize = MTLSizeMake(width, height, 1)
        let region = MTLRegionMake2D(0, 0, width, height)

        if let values = values {
            guard values.count == width * height else {
                print("Error: Provided array size doesn't match texture dimensions")
                return
            }
            texture.replace(region: region, mipmapLevel: 0, withBytes: values, bytesPerRow: bytesPerRow)
        } else {
            // Clear texture to 0
            let zeroBuffer = [Float](repeating: 0, count: width * height)
            texture.replace(region: region, mipmapLevel: 0, withBytes: zeroBuffer, bytesPerRow: bytesPerRow)
        }
    }

}
