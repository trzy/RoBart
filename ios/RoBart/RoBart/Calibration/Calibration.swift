//
//  Calibration.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/8/24.
//

class Calibration {
    /// Height of phone above ground when mounted on robot.
    static let phoneHeightAboveFloor: Float = 1.0

    /// Robot width, height, length: 23.5'' x 38' x 27.5''. Height measured from flat floor to approximate center of phone camera bump.
    static let robotBounds = Vector3(x: 23.5, y: 38, z: 27.5) * 2.54e-2
}
