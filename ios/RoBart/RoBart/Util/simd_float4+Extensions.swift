//
//  simd_float4+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/7/24.
//

import simd

typealias Vector4 = simd_float4

extension Vector4: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        try self.x.write(to: writer)
        try self.y.write(to: writer)
        try self.z.write(to: writer)
        try self.w.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Vector4 {
        let x = try Float.read(from: reader)
        let y = try Float.read(from: reader)
        let z = try Float.read(from: reader)
        let w = try Float.read(from: reader)
        return Vector4(x: x, y: y, z: z, w: w)
    }
}
