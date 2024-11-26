//
//  FollowPath.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/14/24.
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
