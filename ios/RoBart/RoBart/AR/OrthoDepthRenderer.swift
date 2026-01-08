//
//  OrthoDepthRenderer.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/6/24.
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

//
//  Not yet working. Camera transform has been forced to an identity matrix. Setting up a viewport
//  with texture dimensions helped, however still unclear why the test quad at z=1 is mapping to a
//  negative Z value after projection. The Metal vertex shader forces depth to be within range of
//  the NDC volume in order to rasterize anything and have the fragment shader output the expected
//  value.
//

import Metal
import simd

class OrthoDepthRenderer {
    struct Mesh {
        var vertices: MTLBuffer
        var triangles: MTLBuffer
        var transform: Matrix4x4
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthStencilState: MTLDepthStencilState
    private let textureDescriptor: MTLTextureDescriptor
    private let depthTextureDescriptor: MTLTextureDescriptor

    private let textureWidth = 64
    private let textureHeight = 64

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Create pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = device.makeDefaultLibrary()?.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = device.makeDefaultLibrary()?.makeFunction(name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .r32Float
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Create and set vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float3>.stride
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        // Create pipeline state
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
            return nil
        }

        // Create depth stencil state
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .always //.less
        depthStencilDescriptor.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!

        // Create texture descriptor
        self.textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false)
        self.textureDescriptor.usage = [.renderTarget, .shaderRead]
        self.textureDescriptor.storageMode = .shared

        // Create depth texture descriptor
        self.depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false)
        self.depthTextureDescriptor.usage = [.renderTarget]
    }

    func render(meshes meshesIn: [Mesh], cameraPosition: simd_float3, cameraUp: simd_float3 = [0, 1, 0], orthographicScale: Float) -> [Float]? {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let texture = device.makeTexture(descriptor: textureDescriptor),
              let depthTexture = device.makeTexture(descriptor: depthTextureDescriptor) else {
            return nil
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)

//        let depthTexture = device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(
//            pixelFormat: .depth32Float,
//            width: textureWidth,
//            height: textureHeight,
//            mipmapped: false))
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return nil
        }

        let viewport = MTLViewport(originX: 0, originY: 0, width: Double(textureWidth), height: Double(textureHeight), znear: 0, zfar: 1)
        renderEncoder.setViewport(viewport)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setCullMode(.none)

        var viewMatrix = cameraMatrix(eyePosition: cameraPosition, target: cameraPosition - [0, 0, 1], up: cameraUp)
        var projectionMatrix = orthoProjectionMatrix(scale: orthographicScale, near: 0.1, far: 100.0, aspect: Float(textureWidth) / Float(textureHeight))
        //var projectionMatrix = orthographicProjectionMatrix(left: -1, right: 1, bottom: -1, top: 1, near: 0.1, far: 100)

//        var meshes = Array(meshesIn)
        var meshes = createTestQuad()
        print("MESHES: \(meshes.count)")
        for i in 0..<meshes.count {
            renderEncoder.setVertexBuffer(meshes[i].vertices, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&meshes[i].transform, length: MemoryLayout<simd_float4x4>.size, index: 1)
            renderEncoder.setVertexBytes(&viewMatrix, length: MemoryLayout<simd_float4x4>.size, index: 2)
            renderEncoder.setVertexBytes(&projectionMatrix, length: MemoryLayout<simd_float4x4>.size, index: 3)

            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: meshes[i].triangles.length / MemoryLayout<UInt16>.size,
                indexType: .uint16,
                indexBuffer: meshes[i].triangles,
                indexBufferOffset: 0
            )
        }

        renderEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = textureWidth * MemoryLayout<Float>.size
        let region = MTLRegionMake2D(0, 0, textureWidth, textureHeight)
        var depthData = [Float](repeating: 0, count: textureWidth * textureHeight)
        texture.getBytes(&depthData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        return depthData
    }

    private func cameraMatrix(eyePosition eye: Vector3, target: Vector3, up: Vector3) -> Matrix4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        let translateMatrix = simd_float4x4(
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
            [-eye.x, -eye.y, -eye.z, 1]
        )

        let rotateMatrix = simd_float4x4(
            [x.x, y.x, z.x, 0],
            [x.y, y.y, z.y, 0],
            [x.z, y.z, z.z, 0],
            [0, 0, 0, 1]
        )

        //return rotateMatrix * translateMatrix
        return .identity
    }

    private func orthoProjectionMatrix(scale: Float, near: Float, far: Float, aspect: Float) -> Matrix4x4 {
        let r = scale
        let l = -r
        let t = scale / aspect
        let b = -t

        return Matrix4x4(
            [(2.0 / (r - l)), 0, 0, 0],
            [0, (2.0 / (t - b)), 0, 0],
            [0, 0, (-2.0 / (far - near)), 0],
            [-(r + l) / (r - l), -(t + b) / (t - b), -(far + near) / (far - near), 1]
        )
    }

    func orthographicProjectionMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> simd_float4x4 {
        let a = 2.0 / (right - left)
        let b = 2.0 / (top - bottom)
        let c = -2.0 / (far - near)
        let tx = -(right + left) / (right - left)
        let ty = -(top + bottom) / (top - bottom)
        let tz = -(far + near) / (far - near)

        return simd_float4x4(
            [a, 0, 0, 0],
            [0, b, 0, 0],
            [0, 0, c, 0],
            [tx, ty, tz, 1]
        )
    }

    struct Vertex {
        var position: simd_float3
    }

    // Function to generate world space vertices for the quad
    func createTestQuad(scale: Float = 100) -> [Mesh] {
        let z: Float = 1.0
        let quadVertices = [
            Vertex(position: [-scale,  scale, z]), // Top-left
            Vertex(position: [-scale, -scale, z]), // Bottom-left
            Vertex(position: [ scale, -scale, z]), // Bottom-right
            Vertex(position: [ scale,  scale, z])  // Top-right
        ]

        // Indices to draw the two triangles
        let quadIndices: [UInt16] = [
            0, 1, 2, // First triangle: top-left, bottom-left, bottom-right
            0, 2, 3  // Second triangle: top-left, bottom-right, top-right
        ]

        // Create Metal buffers for the quad
        guard let vertexBuffer = device.makeBuffer(bytes: quadVertices,
                                                   length: MemoryLayout<Vertex>.stride * quadVertices.count,
                                                   options: []),
              let indexBuffer = device.makeBuffer(bytes: quadIndices,
                                                  length: MemoryLayout<UInt16>.size * quadIndices.count,
                                                  options: []) else {
            return []
        }

        return [ Mesh(vertices: vertexBuffer, triangles: indexBuffer, transform: .identity) ]
    }


}
