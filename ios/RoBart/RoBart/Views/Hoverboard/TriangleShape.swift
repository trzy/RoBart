//
//  TriangleShape.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
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
