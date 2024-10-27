//
//  simd_float4x4+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import simd

typealias Matrix4x4 = simd_float4x4

extension simd_float4x4 {
    static var identity: simd_float4x4 {
        return .init(diagonal: .one)
    }

    var position: simd_float3 {
        return simd_float3(x: self.columns.3.x, y: self.columns.3.y, z: self.columns.3.z)
    }

    var forward: simd_float3 {
        return simd_float3(x: self.columns.2.x, y: self.columns.2.y, z: self.columns.2.z)
    }

    var up: simd_float3 {
        return simd_float3(x: self.columns.1.x, y: self.columns.1.y, z: self.columns.1.z)
    }

    var right: simd_float3 {
        return simd_float3(x: self.columns.0.x, y: self.columns.0.y, z: self.columns.0.z)
    }

    init(translation: simd_float3, rotation: simd_quatf, scale: simd_float3) {
        let rotationMatrix = simd_matrix4x4(rotation)
        let scaleMatrix = simd_float4x4(diagonal: simd_float4(scale, 1.0))
        let translationMatrix = simd_float4x4(
        [
            simd_float4(x: 1, y: 0, z: 0, w: 0),
            simd_float4(x: 0, y: 1, z: 0, w: 0),
            simd_float4(x: 0, y: 0, z: 1, w: 0),
            simd_float4(translation, 1)
        ])
        let trs = translationMatrix * rotationMatrix * scaleMatrix
        self.init(columns: trs.columns)
    }

    func transformPoint(_ point: Vector3) -> Vector3 {
        let transformed = self * Vector4(point, 1)
        return Vector3(x: transformed.x, y: transformed.y, z: transformed.z)
    }
}

extension simd_float4x4: Codable {
    public func encode(to encoder: any Encoder) throws {
        fatalError("Encodable method encode(to:) not implemented on simd_float4x4")
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        fatalError("Decodable init(from:) not implemented on simd_float4x4")
    }
}

extension Matrix4x4: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        try self.columns.0.write(to: writer)
        try self.columns.1.write(to: writer)
        try self.columns.2.write(to: writer)
        try self.columns.3.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Matrix4x4 {
        let column0 = try Vector4.read(from: reader)
        let column1 = try Vector4.read(from: reader)
        let column2 = try Vector4.read(from: reader)
        let column3 = try Vector4.read(from: reader)
        return Matrix4x4(column0, column1, column2, column3)
    }
}
