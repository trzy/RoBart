//
//  FollowPath.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/14/24.
//

import Foundation

func followPath(_ path: [Vector3]) async throws {
    for i in 0..<path.count {
        log("Moving to path[\(i)] = \(path[i])...")
        
        // Face the next waypoint
        let towardWaypoint = (path[i] - ARSessionManager.shared.transform.position).xzProjected
        HoverboardController.shared.send(.face(forward: towardWaypoint))
        try await Task.sleep(timeout: .seconds(2), while: { HoverboardController.shared.isMoving })

        // Move to waypoint
        HoverboardController.shared.send(.driveTo(position: path[i]))
        try await Task.sleep(timeout: .seconds(10), while: { HoverboardController.shared.isMoving })

        log("At path[\(i)]")
    }
}

fileprivate func log(_ message: String) {
    print("[FollowPath] \(message)")
}
