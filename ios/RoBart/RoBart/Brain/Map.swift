//
//  Map.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/29/24.
//

import UIKit

func renderMap(occupancy map: OccupancyMap, ourTransform: Matrix4x4, navigablePoints: [AnnotatingCamera.NavigablePoint] = []) -> UIImage? {
    let pixLength = 10
    let navigablePointSideLength = 2 * pixLength
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

    // Render navigable points as numeric annotations
    for point in navigablePoints {
        // Draw square. Note that when rotating image clockwise and using an upper-left
        // origin with +y as down, it is necessary to invert x (because +y in the original
        // image moves down, but rotated clockwise, that direction is -x instead of +x).
        let cell = map.positionToCell(point.worldPoint)
        let x = cell.cellX * pixLength
        let z = cell.cellZ * pixLength
        let squareRect = CGRect(x: x, y: z, width: navigablePointSideLength, height: navigablePointSideLength)
        context.setFillColor(point.backgroundColor)
        context.fill(squareRect)

        // Draw number in center of square
        let text = "\(point.id)"
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(navigablePointSideLength) / 2, weight: .bold),
            .foregroundColor: point.textColor
        ]
        let textSize = text.size(withAttributes: textAttributes)
        let textX = squareRect.midX - textSize.width / 2
        let textY = squareRect.midY - textSize.height / 2
        let textRect = CGRect(x: textX, y: textY, width: textSize.width, height: textSize.height)
        text.draw(in: textRect, withAttributes: textAttributes)
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
