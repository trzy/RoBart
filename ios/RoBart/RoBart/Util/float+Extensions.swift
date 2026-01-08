//
//  float+Extensions.swift
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

extension Float {
    static let rad2Deg = Float(180.0) / Float.pi
    static let deg2Rad = Float.pi / Float(180.0)

    func map(oldMin: Float, oldMax: Float, newMin: Float, newMax: Float) -> Float {
        return newMin + (newMax - newMin) * (self - oldMin) / (oldMax - oldMin)
    }

    func mapClamped(oldMin: Float, oldMax: Float, newMin: Float, newMax: Float) -> Float {
        let remapped = self.map(oldMin: oldMin, oldMax: oldMax, newMin: newMin, newMax: newMax)
        return max(min(remapped, newMax), newMin)
    }
}
