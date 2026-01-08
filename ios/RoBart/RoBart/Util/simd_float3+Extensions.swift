//
//  simd_float3+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
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

typealias Vector3 = simd_float3

extension simd_float3 {
    static var forward: simd_float3 {
        return simd_float3(x: 0, y: 0, z: 1)
    }

    static var up: simd_float3 {
        return simd_float3(x: 0, y: 1, z: 0)
    }

    static var right: simd_float3 {
        return simd_float3(x: 1, y: 0, z: 0)
    }

    static func dot(_ u: simd_float3, _ v: simd_float3) -> Float {
        return simd_dot(u, v)
    }

    static func angle(_ u: simd_float3, _ v: simd_float3) -> Float {
        let cosine = Vector3.dot(u, v) / (u.magnitude * v.magnitude)
        return acos(RoBart.clamp(cosine, min: -1.0, max: 1.0)) * .rad2Deg
    }

    static func signedAngle(from u: simd_float3, to v: simd_float3, axis: simd_float3) -> Float {
        let unsignedAngle = Vector3.angle(u, v)
        let crossX = u.y * v.z - u.z * v.y
        let crossY = -(u.x * v.z - u.z * v.x)
        let crossZ = u.x * v.y - u.y * v.x
        let dot = (axis.x * crossX + axis.y * crossY + axis.z * crossZ)
        let sign: Float = dot >= 0 ? 1.0 : -1.0
        return unsignedAngle * sign
    }

    func rotated(by degrees: Float, about axis: simd_float3) -> simd_float3 {
        return simd_quatf(angle: degrees * .deg2Rad, axis: axis.normalized).act(self)
    }

    var normalized: simd_float3 {
        return simd_normalize(self)
    }

    var magnitude: Float {
        return simd_length(self)
    }

    var sqrMagnitude: Float {
        return simd_length_squared(self)
    }

    var distance: Float {
        return simd_length(self)
    }

    var xzProjected: simd_float3 {
        return simd_float3(x: self.x, y: 0, z: self.z)
    }
}
