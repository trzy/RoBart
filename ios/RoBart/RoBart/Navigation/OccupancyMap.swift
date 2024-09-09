//
//  OccupancyMap.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/7/24.
//

import CoreVideo
import Foundation
import simd
import UIKit

class OccupancyMap {
    let width: Float
    let depth: Float
    let centerPoint: Vector3
    let cellsWide: Int
    let cellsDeep: Int
    let cellWidth: Float
    let cellDepth: Float

    private var _occupancy: [Float] // can be either a count of observations within cell or cell occupancy
    private var _worldPosition: [Vector3]

    init(width: Float, depth: Float, cellWidth: Float, cellDepth: Float, centerPoint: Vector3) {
        assert(cellWidth <= width)
        assert(cellDepth <= depth)
        
        let cellsWide = Int(floor(width / cellWidth))
        let cellsDeep = Int(floor(depth / cellDepth))
        _occupancy = Array(repeating: Float(0), count: cellsWide * cellsDeep)
        
        self.width = width
        self.depth = depth
        self.centerPoint = centerPoint

        self.cellsWide = cellsWide
        self.cellsDeep = cellsDeep
        self.cellWidth = cellWidth
        self.cellDepth = cellDepth

        // World position at center point of each cell
        _worldPosition = Array(repeating: Vector3.zero, count: cellsWide * cellsDeep)
        let center = centerCell()
        var z = centerPoint.z - cellDepth * Float(center.cellZ)
        for zi in 0..<cellsDeep {
            var x = centerPoint.x - cellWidth * Float(center.cellX)
            for xi in 0..<cellsWide {
                _worldPosition[gridIndex(cellX: xi, cellZ: zi)] = Vector3(x: x, y: 0, z: z)
                x += cellWidth
            }
            z += cellDepth
        }
    }

    private func gridIndex(cellX: Int, cellZ: Int) -> Int {
        return cellZ * cellsWide + cellX
    }

    private func centerCell() -> (cellX: Int, cellZ: Int) {
        return (cellX: Int(round(Float(cellsWide) * 0.5)), cellZ: Int(round(Float(cellsDeep) * 0.5)))
    }

    private func centerIndex() -> Int {
        let center = centerCell()
        return gridIndex(cellX: center.cellX, cellZ: center.cellZ)
    }

    /// Given a world space position (x, y, z), finds the height map cell indices. Coordinates
    /// outside the map boundaries are clamped to the outer cells.
    /// - Parameter position: World position.
    /// - Returns: The integral x and z cell indices of the cell containing the world point or, if
    /// the coordinate is out of bounds, the nearest cell on the perimeter.
    private func positionToIndices(position: Vector3) -> (cellX: Int, cellZ: Int) {
        let centerCell = centerCell()
        let gridCenterPoint = _worldPosition[centerIndex()]
        var xi = Int(floor((position.x - gridCenterPoint.x) / cellWidth + 0.5)) + centerCell.cellX
        var zi = Int(floor((position.z - gridCenterPoint.z) / cellDepth + 0.5)) + centerCell.cellZ
        xi = min(max(0, xi), cellsWide - 1)
        zi = min(max(0, zi), cellsDeep - 1)
        return (cellX: xi, cellZ: zi)
    }

    /// Given a world space position (x, y, z), finds the height map cell indices as floats. These
    /// may be fractional (e.g., (1.05, 23.42)). Cell coordinates are clamped between -0.5 and
    /// (numCells - 1 + 0.5) along each axis.
    /// - Parameter position: World position.
    /// - Returns: The decimal x and z cell indices
    private func positionToFractionalIndices(position: Vector3) -> (cellX: Float, cellZ: Float) {
        let centerCell = centerCell()
        let gridCenterPoint = _worldPosition[centerIndex()]
        var xf = ((position.x - gridCenterPoint.x) / cellWidth) + Float(centerCell.cellX)
        var zf = ((position.z - gridCenterPoint.z) / cellDepth) + Float(centerCell.cellZ)

        // Clamp to edges. Note that the only difference between this function and positionToIndices()
        // is that the latter adds 0.5 and then floors. Therefore, we know the limits are: [-0.5, s_numCells - 1 + 0.5).
        xf = min(max(-0.5, xf), cellWidth - 1.0 + 0.5)
        zf = min(max(-0.5, zf), cellDepth - 1.0 + 0.5)
        return (cellX: xf, cellZ: zf)
    }

    func clear() {
        for i in 0..<_occupancy.count {
            _occupancy[i] = 0
        }
    }

    func updateObservations(depthMap: CVPixelBuffer, intrinsics: Matrix3x3, rgbResolution: CGSize, viewMatrix: Matrix4x4, floorY: Float) {
        guard let depthValues = depthMap.toFloatArray() else { return }

        // Get depth intrinsic parameters
        let scaleX = Float(depthMap.width) / Float(rgbResolution.width)
        let scaleY = Float(depthMap.height) / Float(rgbResolution.height)
        let fx = intrinsics[0,0] * scaleX
        let cx = intrinsics[2,0] * scaleX   // note: (column, row)
        let fy = intrinsics[1,1] * scaleY
        let cy = intrinsics[2,1] * scaleY

        // Create a depth camera to world matrix. The depth image coordinate system happens to be
        // almost the same as the ARKit camera system, except y is flipped (everything rotated 180
        // degrees about the x axis, which points down in portrait orientation).
        let rotateDepthToARKit = Quaternion(angle: .pi, axis: .right)
        let cameraToWorld = viewMatrix * Matrix4x4(translation: .zero, rotation: rotateDepthToARKit, scale: .one)

        // Check each point and update observations
        var idx = 0
        for yi in 0..<depthMap.height {
            for xi in 0..<depthMap.width {
                // Get depth point
                let depth = depthValues[idx]    // use positive depth directly in these calculations
                idx += 1

                // Works best with mid-range depth points
                if depth < 1  || depth > 3 {
                    continue
                }

                // Compute its world position
                let cameraSpacePos = Vector3(x: depth * (Float(xi) - cx) / fx , y: depth * (Float(yi) - cy) / fy, z: depth)
                let worldPos = cameraToWorld.transformPoint(cameraSpacePos)

                // Ignore floor and ceiling -- TODO: need to find floor as minimum ground plane!
                if (worldPos.y < (floorY + 0.25)) || (worldPos.y > Calibration.phoneHeight) {
                    continue
                }
//                if (worldPos.y < -0.1) || (worldPos.y > 0.1) {
//                    continue
//                }

                // Count LiDAR points found
                let cell = positionToIndices(position: worldPos)
                _occupancy[gridIndex(cellX: cell.cellX, cellZ: cell.cellZ)] += 1.0
            }
        }
    }

    func updateOccupancyFromObservations(from countMap: OccupancyMap, observationThreshold: Float) {
        assert(countMap._occupancy.count == _occupancy.count)
        let counts = countMap._occupancy
        for i in 0..<counts.count {
            if counts[i] >= observationThreshold {
                _occupancy[i] = 1.0
            }
        }
    }

    func render() -> UIImage? {
        let pixLength = 10
        let imageSize = CGSize(width: cellsWide * pixLength, height: cellsDeep * pixLength)

        // Create a graphics context to draw the image
        UIGraphicsBeginImageContext(imageSize)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Loop through the occupancy grid and draw squares
        for z in 0..<cellsDeep {
            for x in 0..<cellsWide {
                let index = z * cellsWide + x
                let isOccupied = _occupancy[index] > 0

                // Set the color based on occupancy
                let color: UIColor = isOccupied ? .red : .white
                context.setFillColor(color.cgColor)

                // Define the square's rectangle
                let rect = CGRect(x: x * pixLength, y: z * pixLength, width: pixLength, height: pixLength)

                // Draw the rectangle
                context.fill(rect)
            }
        }

        // Retrieve the generated image
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }
}
