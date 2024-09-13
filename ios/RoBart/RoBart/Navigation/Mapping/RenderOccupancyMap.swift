//
//  RenderOccupancy.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/12/24.
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

    // Draw path, if one given
    context.setFillColor(UIColor.black.cgColor)
    for position in path {
        // Position -> cell indices
        let cell = map.positionToIndices(position)
        let cellX = Int(cell.first)
        let cellZ = Int(cell.second)

        // A slightly smaller rect
        let crumbLength = pixLength / 2
        let x = cellX * pixLength + (pixLength - crumbLength) / 2
        let y = cellZ * pixLength + (pixLength - crumbLength) / 2
        let rect = CGRect(x: x, y: y, width: crumbLength, height: crumbLength)
        context.fill(rect)
    }

    // Draw circle at our current position
    let ourCell = map.positionToIndices(ourTransform.position)
    let ourCellX = CGFloat(ourCell.first)
    let ourCellY = CGFloat(ourCell.second)
    let ourPosX = (ourCellX + 0.5) * CGFloat(pixLength)
    let ourPosY = (ourCellY + 0.5) * CGFloat(pixLength)
    context.setFillColor(UIColor.red.cgColor)
    let center = CGPoint(x: ourPosX, y: ourPosY)
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
    let posFarInFront = simd_float2((Float(cellInFront.first) + 0.5 ) * Float(pixLength), (Float(cellInFront.second) + 0.5 ) * Float(pixLength))
    let posCenter = simd_float2(Float(ourPosX), Float(ourPosY))
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
