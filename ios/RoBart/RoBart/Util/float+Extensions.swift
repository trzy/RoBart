//
//  float+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

extension Float {
    static let rad2Deg = Float(180.0) / Float.pi
    static let deg2Rad = Float.pi / Float(180.0)

    func map(oldMin: Float, oldMax: Float, newMin: Float, newMax: Float) -> Float {
        return newMin + (newMax - newMin) * (self - oldMin) / (oldMax - oldMin)
    }

    func mapClamped(oldMin: Float, oldMax: Float, newMin: Float, newMax: Float) -> Float {
        let remapped = self.map(oldMin: oldMin, oldMax: oldMax, newMin: newMin, newMax: newMax)
        return max(min(remapped, newMax), newMin)
    }

    static func lerp(from a: Float, to b: Float, t: Float) -> Float {
        return a + (b - a) * min(max(0, t), 1)
    }
}
