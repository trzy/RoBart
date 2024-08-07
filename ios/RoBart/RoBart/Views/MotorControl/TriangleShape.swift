//
//  TriangleShape.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

struct TriangleShape: Shape {
    enum Direction {
        case up
        case down
        case left
        case right
    }

    private let _direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch _direction {
        case .up:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))      // bottom left
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))   // top middle
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))   // bottom right
        case .down:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))      // top left
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))   // bottom middle
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))   // top right
        case .left:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))      // top right
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))   // left middle
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))   // bottom right
        case .right:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))      // top left
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))   // right middle
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))   // bottom left
        }
        path.closeSubpath()
        return path
    }

    init(direction: Direction) {
        _direction = direction
    }
}
