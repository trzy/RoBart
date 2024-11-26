//
//  simd_float4+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/7/24.
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
