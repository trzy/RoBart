//
//  NavigateToGoal.swift
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

//
//  TODO:
//  -----
//  - Smaller cells work better. Will need to do bounds testing during pathfinding.
//

import Foundation

func navigateToGoal(position goal: Vector3) async throws {
    // Keep trying to reach the goal
    var rescan = true
    var originalPath: [Vector3]?
    while !reachedGoal(goal) {
        if rescan {
            // Take a look around so ARKit can analyze the environment
            try await scan360()
        }

        // Obtain new waypoints if needed. If unable, try to rescan unless we already have.
        let currentPosition = ARSessionManager.shared.transform.position
        if originalPath == nil {
            originalPath = await updatePath(to: goal, from: currentPosition)
        }
        guard let path = originalPath else {
            if rescan {
                // Already scanned this iteration, no path found. Must abort.
                break
            } else {
                rescan = true
                continue
            }
        }
        rescan = false
        try Task.checkCancellation()

        // Drive to next waypoint
        guard let nextPosition = path.first else {
            HoverboardController.shared.send(.drive(leftThrottle: 0, rightThrottle: 0))
            break
        }
        log("Driving to: \(nextPosition), steps remaining: \(path.count)")
        HoverboardController.shared.send(.driveTo(position: nextPosition))
        try await Task.sleep(timeout: .seconds(10), while: { HoverboardController.shared.isMoving })
//        try await Task.sleep(for: .seconds(1))
//        break
        originalPath!.removeFirst()  // next
        log("At: \(ARSessionManager.shared.transform.position.xzProjected)")

    }
}

fileprivate func reachedGoal(_ goal: Vector3) -> Bool {
    let currentPosition = ARSessionManager.shared.transform.position
    return (goal - currentPosition).magnitude <= HoverboardController.shared.positionGoalTolerance
}

fileprivate func updatePath(to goal: Vector3, from startPosition: Vector3) async -> [Vector3]? {
    // Update occupancy
    let succeeded = await NavigationController.shared.updateOccupancy()
    if !succeeded {
        return nil
    }

    // Compute path
    var timer = Util.Stopwatch()
    timer.start()
    let from = ARSessionManager.shared.transform.position;
    let to = goal
    let robotRadius = 0.5 * max(Calibration.robotBounds.x, Calibration.robotBounds.z)
    let pathCells = findPath(NavigationController.shared.occupancy, from, to, robotRadius)

    // Convert path to positions
    let pathPositions = pathCells.map { NavigationController.shared.occupancy.cellToPosition($0) }
    log("Path computed: \(timer.elapsedMilliseconds()) ms")

    // Debug: send to handheld phones for visualization
    sendToHandheldPeers(path: pathPositions)

    return pathPositions.isEmpty ? nil : pathPositions
}

fileprivate func sendToHandheldPeers(path: [Vector3]) {
    // Send occupancy map and path to peers
    let msg = PeerOccupancyMessage(
        width: NavigationController.shared.occupancy.width(),
        depth: NavigationController.shared.occupancy.depth(),
        cellSide: NavigationController.shared.occupancy.cellSide(),
        centerPoint: NavigationController.shared.occupancy.centerPoint(),
        occupancy: NavigationController.shared.getOccupancyArray(),
        path: path,
        ourTransform: ARSessionManager.shared.transform
    )
    PeerManager.shared.send(msg, toPeersWithRole: .handheld, reliable: true)
}

fileprivate func log(_ message: String) {
    print("[NavigateToGoal] \(message)")
}
