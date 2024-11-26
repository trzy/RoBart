//
//  RenderOccupancy.swift
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

import UIKit

func renderOccupancyMap(occupancy map: OccupancyMap, ourTransform: Matrix4x4, path: [Vector3] = []) -> UIImage? {
    let pixLength = 10
    let imageSize = CGSize(width: map.cellsWide() * pixLength, height: map.cellsDeep() * pixLength)

    // Create a graphics context to draw the image
    UIGraphicsBeginImageContext(imageSize)
    guard let context = UIGraphicsGetCurrentContext() else { return nil }

    // Loop through the occupancy grid and draw squares
    for zi in 0..<map.cellsDeep() {
        for xi in 0..<map.cellsWide() {
            let isOccupied = map.at(xi, zi) > 0

            // Set the color based on occupancy
            let color: UIColor = isOccupied ? .blue : .white
            context.setFillColor(color.cgColor)

            // Define the square's rectangle
            let rect = CGRect(x: xi * pixLength, y: zi * pixLength, width: pixLength, height: pixLength)

            // Draw the rectangle
            context.fill(rect)
        }
    }

    // Draw path, if one given. But first need to convert back to cells.
    let pathCells = path.map { map.positionToCell($0) }
    context.setFillColor(UIColor.black.cgColor)
    for i in 0..<pathCells.count {
        // Draw breadcrumbs between path waypoints
        let cellFrom = pathCells[i]
        let cellTo = (i + 1) >= pathCells.count ? cellFrom : pathCells[i + 1]
        let stepX = (cellTo.cellX - cellFrom.cellX).signum()    // -1, 0, or 1
        let stepZ = (cellTo.cellZ - cellFrom.cellZ).signum()
        if stepX != 0 && stepZ != 0 {
            fatalError("Diagonal paths not yet supported")
        }

        var cell = cellFrom
        repeat {
            // A slightly smaller rect
            let crumbLength = pixLength / 2
            let x = cell.cellX * pixLength + (pixLength - crumbLength) / 2
            let y = cell.cellZ * pixLength + (pixLength - crumbLength) / 2
            let rect = CGRect(x: x, y: y, width: crumbLength, height: crumbLength)
            context.fill(rect)

            // Next step (this only works because only one of deltaX, deltaZ will be non-zero)
            cell.cellX += stepX
            cell.cellZ += stepZ
        } while cell != cellTo
    }

    // Draw circle at our current position
    let ourCell = map.positionToCell(ourTransform.position)
    let ourCellX = CGFloat(ourCell.cellX)
    let ourCellZ = CGFloat(ourCell.cellZ)
    let ourPosX = (ourCellX + 0.5) * CGFloat(pixLength)
    let ourPosZ = (ourCellZ + 0.5) * CGFloat(pixLength)
    context.setFillColor(UIColor.red.cgColor)
    let center = CGPoint(x: ourPosX, y: ourPosZ)
    let path = UIBezierPath(
        arcCenter: center,
        radius: 0.5 * CGFloat(pixLength),
        startAngle: 0,
        endAngle: 2 * .pi,
        clockwise: true
    )
    path.fill()

    // Draw a little line in front of our current heading
    let inFront = ourTransform.position - 1.0 * ourTransform.forward.xzProjected
    let cellInFront = map.positionToFractionalIndices(inFront)
    let posFarInFront = simd_float2((cellInFront.cellX + 0.5 ) * Float(pixLength), (cellInFront.cellZ + 0.5 ) * Float(pixLength))
    let posCenter = simd_float2(Float(ourPosX), Float(ourPosZ))
    let forwardDir = simd_normalize(posFarInFront - posCenter)
    let linePath = UIBezierPath()
    linePath.move(to: center)
    linePath.addLine(to: CGPoint(x: center.x + CGFloat(forwardDir.x) * CGFloat(2 * pixLength), y: center.y + CGFloat(forwardDir.y) * CGFloat(2 * pixLength)))
    context.setStrokeColor(UIColor.red.cgColor)
    linePath.stroke()

    // Retrieve the generated image
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image
}
