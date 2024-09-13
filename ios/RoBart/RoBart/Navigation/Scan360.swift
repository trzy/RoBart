//
//  Scan360.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
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
