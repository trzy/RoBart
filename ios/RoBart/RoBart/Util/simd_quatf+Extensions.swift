//
//  simd_quatf+Extensions.swift
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

typealias Quaternion = simd_quatf

extension simd_quatf {
    static var identity: simd_quatf {
        return simd_quatf(real: 1, imag: .zero)
    }

    static func lookRotation(forward: simd_float3, up: simd_float3 = .up) -> simd_quatf {
        let forward = forward.normalized

        let vector = forward
        let vector2 = simd_cross(up, vector).normalized
        let vector3 = simd_cross(vector, vector2)

        let m00 = vector2.x
        let m01 = vector2.y
        let m02 = vector2.z
        let m10 = vector3.x
        let m11 = vector3.y
        let m12 = vector3.z
        let m20 = vector.x
        let m21 = vector.y
        let m22 = vector.z

        let num8 = m00 + m11 + m22

        if num8 > 0 {
            var num = sqrt(num8 + 1.0)
            let w = 0.5 * num
            num = 0.5 / num
            let x = (m12 - m21) * num
            let y = (m20 - m02) * num
            let z = (m01 - m10) * num
            return simd_quatf(ix: x, iy: y, iz: z, r: w)
        }

        if m00 >= m11 && m00 >= m22 {
            let num7 = sqrt(1.0 + m00 - m11 - m22)
            let num4 = 0.5 / num7
            let x = 0.5 * num7
            let y = (m01 + m10) * num4
            let z = (m02 + m20) * num4
            let w = (m12 - m21) * num4
            return simd_quatf(ix: x, iy: y, iz: z, r: w)
        }

        if m11 > m22 {
            let num6 = sqrt(1.0 + m11 - m00 - m22)
            let num3 = 0.5 / num6
            let x = (m10 + m01) * num3
            let y = 0.5 * num6
            let z = (m21 + m12) * num3
            let w = (m20 - m02) * num3
            return simd_quatf(ix: x, iy: y, iz: z, r: w)
        }

        let num5 = sqrt(1.0 + m22 - m00 - m11)
        let num2 = 0.5 / num5
        let x = (m20 + m02) * num2
        let y = (m21 + m12) * num2
        let z = 0.5 * num5
        let w = (m01 - m10) * num2
        return simd_quatf(ix: x, iy: y, iz: z, r: w)
    }
}
