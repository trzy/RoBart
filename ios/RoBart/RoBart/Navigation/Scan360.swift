//
//  Scan360.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
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

import Foundation

/// Spin around slowly 360 degrees. Useful for mapping local surroundings.
func scan360() async throws {
    // Divide the circle into 45 degree arcs, ending on our starting orientation
    let startingForward = -ARSessionManager.shared.transform.forward
    var steps: [Vector3] = []
    for i in 1...7 {
        steps.append(startingForward.rotated(by: Float(45 * i), about: .up))
    }
    steps.append(startingForward)   // return to initial position

    // Move between them with a timeout in case we get stuck or hit something
    let deadline = Date.now.advanced(by: 10)
    for targetForward in steps {
        log("Target forward: \(targetForward)")
        HoverboardController.shared.send(.face(forward: targetForward))
        try await Task.sleep(withDeadline: deadline, while: { HoverboardController.shared.isMoving })
    }
}

fileprivate func log(_ message: String) {
    print("[Scan360] \(message)")
}
