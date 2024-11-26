//
//  Calibration.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
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

class Calibration {
    /// Height of phone above ground when mounted on robot.
    static let phoneHeightAboveFloor: Float = 1.0

    /// Robot width, height, length: 23.5'' x 38' x 27.5''. Height measured from flat floor to approximate center of phone camera bump.
    static let robotBounds = Vector3(x: 23.5, y: 38, z: 27.5) * 2.54e-2
}
