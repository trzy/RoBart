//
//  NavigateToGoal.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
//
//  TODO:
//  -----
//  - Smaller cells work better. Will need to do bounds testing during pathfinding.
//

import Foundation

func navigateToGoal(position goal: Vector3) async throws {
    // Occupancy map
    let occupancyCalculator = GPUOccpancyMap(
        width: 20,
        depth: 20,
        cellWidth: 0.25,
        cellDepth: 0.25,
        centerPoint: ARSessionManager.shared.transform.position
    )
    var occupancy = OccupancyMap(
        occupancyCalculator.width,
        occupancyCalculator.depth,
        occupancyCalculator.cellWidth,
        occupancyCalculator.cellDepth,
        occupancyCalculator.centerPoint
    )

    // Keep trying to reach the goal
    var rescan = true
    var path: [Vector3]?
    while !reachedGoal(goal) {
        if rescan {
            // Take a look around so ARKit can analyze the environment
            try await scan360()
        }

        // Obtain new waypoints if needed. If unable, try to rescan unless we already have.
        let currentPosition = ARSessionManager.shared.transform.position
        if path == nil {
            path = await updatePath(to: goal, from: currentPosition, occupancyCalculator: occupancyCalculator, occupancy: &occupancy)
        }
        guard let path = path else {
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
//        let nextPosition = path.first!
//        HoverboardController.shared.send(.driveTo(position: nextPosition))
//        try await Task.sleep(timeout: .seconds(10), while: { HoverboardController.shared.isMoving })
        try await Task.sleep(for: .seconds(1))
        break
    }
}

fileprivate func reachedGoal(_ goal: Vector3) -> Bool {
    let currentPosition = ARSessionManager.shared.transform.position
    return (goal - currentPosition).magnitude <= HoverboardController.shared.positionGoalTolerance
}

fileprivate func updatePath(to goal: Vector3, from startPosition: Vector3, occupancyCalculator: GPUOccpancyMap, occupancy: inout OccupancyMap) async -> [Vector3]? {
    var timer = Util.Stopwatch()
    timer.start()

    // Unbundle all meshes into a linear array of vertices and associate a transform with each
    var vertices: [Vector3] = []
    var transforms: [Matrix4x4] = []
    var transformIdxs: [UInt32] = []
    let meshes = ARSessionManager.shared.sceneMeshes
    var transformIdx: UInt32 = 0
    for mesh in meshes {
        transforms.append(mesh.transform)
        for vertex in mesh.vertices {
            vertices.append(vertex)
            transformIdxs.append(transformIdx)
        }
        transformIdx += 1
    }

    // Calculate occupancy on GPU
    let minHeight = ARSessionManager.shared.floorY + 0.25
    let maxHeight = ARSessionManager.shared.floorY + Calibration.phoneHeightAboveFloor
    occupancyCalculator.reset(to: 0)
    guard let _ = await occupancyCalculator.update(
        vertices: vertices,
        transforms: transforms,
        transformIndices: transformIdxs,
        minOccupiedHeight: minHeight,
        maxOccupiedHeight: maxHeight
    ) else {
        // Operation failed, no path can be produced
        return nil
    }

    // Update occupancy map from GPU result
    guard let occupancyArray = occupancyCalculator.getMapArray() else {
        return nil
    }
    occupancyArray.withUnsafeBufferPointer { ptr in
        occupancy.updateOccupancyFromArray(ptr.baseAddress, occupancyArray.count)
    }
    log("Occupancy updated: \(timer.elapsedMilliseconds()) ms")

    // Compute path
    timer.start()
    let from = ARSessionManager.shared.transform.position;
    let to = goal
    let pathCells = findPath(occupancy, from, to)

    // Convert path to positions
    let pathPositions = pathCells.map { occupancy.cellToPosition($0) }
    log("Path computed: \(timer.elapsedMilliseconds()) ms")

    // Debug: send to handheld phones for visualization
    sendToHandheldPeers(occupancy: occupancy, path: pathPositions)

    return pathPositions.isEmpty ? nil : pathPositions
}

fileprivate func sendToHandheldPeers(occupancy: OccupancyMap, path: [Vector3]) {
    // Occupancy as flat array
    var occupancyArray: [Float] = []
    for zi in 0..<occupancy.cellsDeep() {
        for xi in 0..<occupancy.cellsWide() {
            occupancyArray.append(occupancy.at(xi, zi))
        }
    }

    // Send to peers
    let msg = PeerOccupancyMessage(
        width: occupancy.width(),
        depth: occupancy.depth(),
        cellWidth: occupancy.cellWidth(),
        cellDepth: occupancy.cellDepth(),
        centerPoint: occupancy.centerPoint(),
        occupancy: occupancyArray,
        path: path,
        ourTransform: ARSessionManager.shared.transform
    )
    PeerManager.shared.send(msg, toPeersWithRole: .handheld, reliable: true)
}

fileprivate func log(_ message: String) {
    print("[NavigateToGoal] \(message)")
}
