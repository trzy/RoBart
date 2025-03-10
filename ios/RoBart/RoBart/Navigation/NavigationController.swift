//
//  NavigationController.swift
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

enum NavigationCommand {
    case navigate(to: Vector3)
    case scan360
    case follow(path: [Vector3])
}

class NavigationController {
    static let shared = NavigationController()

    static let cellSide: Float = 0.25

    private var _nextCommand: NavigationCommand?
    private var _currentTask: Task<Void, Never>?

    private lazy var _occupancyCalculator: GPUOccupancyMap = {
        return GPUOccupancyMap(
            width: 20,
            depth: 20,
            cellSide: Self.cellSide,
            centerPoint: ARSessionManager.shared.transform.position
        )
    }()

    lazy var occupancy: OccupancyMap = {
        return OccupancyMap(
            _occupancyCalculator.width,
            _occupancyCalculator.depth,
            _occupancyCalculator.cellSide,
            _occupancyCalculator.centerPoint
        )
    }()

    fileprivate init() {
    }

    func runTask() async {
        while true {
            // Await next navigation command
            guard let command = _nextCommand else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            _nextCommand = nil

            // Execute command
            _currentTask = Task {
                do {
                    switch command {
                    case .navigate(to: let position):
                        log("Navigating to \(position)")
                        try await navigateToGoal(position: position)
                    case .scan360:
                        log("Scanning 360 degrees")
                        try await scan360()
                    case .follow(path: let path):
                        log("Following path")
                        try await followPath(path)
                    }
                } catch {
                    log("Command interrupted: \(error.localizedDescription)")
                }
            }
            _ = await _currentTask!.result
        }
    }

    /// Attempts to stop the currently-running navigation task. Because tasks are cooperative,
    /// there is no guarantee when or whether this will stop the task.
    func stopNavigation() {
        _currentTask?.cancel()
    }

    func run(_ command: NavigationCommand) {
        stopNavigation()
        _nextCommand = command
    }

    /// Updates the occupancy map with the current scene geometry.
    /// - Returns: `true` if successful, `false` if the occupancy was not updated for any reason.
    func updateOccupancy() async -> Bool {
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
        _occupancyCalculator.reset(to: 0)
        guard let _ = await _occupancyCalculator.update(
            vertices: vertices,
            transforms: transforms,
            transformIndices: transformIdxs,
            minOccupiedHeight: minHeight,
            maxOccupiedHeight: maxHeight
        ) else {
            // Operation failed
            return false
        }

        // Update occupancy map from GPU result
        guard let occupancyArray = _occupancyCalculator.getMapArray() else {
            return false
        }
        occupancyArray.withUnsafeBufferPointer { ptr in
            occupancy.updateOccupancyFromArray(ptr.baseAddress, occupancyArray.count)
        }
        log("Occupancy updated: \(timer.elapsedMilliseconds()) ms")

        return true
    }

    func getOccupancyArray() -> [Float] {
        var array = Array(repeating: Float(0), count: occupancy.numCells())
        array.withUnsafeMutableBufferPointer { ptr in
            occupancy.getOccupancyArray(ptr.baseAddress, occupancy.numCells())
        }
        return array
    }
}

fileprivate func log(_ message: String) {
    print("[NavigationController] \(message)")
}
