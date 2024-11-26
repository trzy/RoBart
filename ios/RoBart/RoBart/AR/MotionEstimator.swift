//
//  MotionEstimator.swift
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

import ARKit

class MotionEstimator {
    private static let _numSamples = 5
    private var _velocitySamples = Array(repeating: Vector3.zero, count: _numSamples)
    private var _angularVelocitySamples = Array(repeating: Float(0), count: _numSamples)
    private var _dtSamples = Array(repeating: Float.zero, count: _numSamples)
    private var _prevPosition: Vector3?
    private var _prevForward: Vector3?
    private var _prevFrameTime: TimeInterval = 0
    private var _velocityEstimate = Vector3.zero
    private var _prevVelocityEstimate = Vector3.zero
    private var _accelerationEstimate = Vector3.zero
    private var _angularVelocityEstimate: Float = 0
    private var _totalSampleCount = 0

    var velocity: Vector3 {
        return _velocityEstimate.xzProjected
    }

    var speed: Float {
        return velocity.magnitude
    }

    var acceleration: Vector3 {
        return _accelerationEstimate.xzProjected
    }

    var angularVelocity: Float {
        return _angularVelocityEstimate
    }

    func update(_ frame: ARFrame) {
        let currentPosition = frame.camera.transform.position
        let currentForward = -frame.camera.transform.forward    // forward points out of screen, -forward for direction of phone back camera and therefore the hoverboard
        let currentTime = frame.timestamp

        if let prevPosition = _prevPosition,
           let prevForward = _prevForward {
            let dt = Float(currentTime - _prevFrameTime)
            let idx = _totalSampleCount % Self._numSamples
            _velocitySamples[idx] = (currentPosition - prevPosition) / dt
            _angularVelocitySamples[idx] = degreesRotated(prevForward: prevForward, currentForward: currentForward) / dt
            _dtSamples[idx] = dt
            _totalSampleCount += 1
        }

        _prevPosition = currentPosition
        _prevForward = currentForward
        _prevFrameTime = currentTime

        updateVelocityEstimate()
        updateAccelerationEstimate()
        updateAngularVelocityEstimate()

        //log("Velocity: \(speed), Acceleration: \(acceleration.magnitude)")
    }

    private func updateVelocityEstimate() {
        var velocity = Vector3.zero
        if _totalSampleCount > 0 {
            let populatedSamples = min(Self._numSamples, _totalSampleCount)
            for i in 0..<populatedSamples {
                velocity += _velocitySamples[i]
            }
            velocity *= (1.0 / Float(populatedSamples))
        }
        _prevVelocityEstimate = _velocityEstimate
        _velocityEstimate = velocity
    }

    private func updateAccelerationEstimate() {
        var acceleration = Vector3.zero
        var n = 0
        var i = _totalSampleCount - _velocitySamples.count + 2
        while i < _totalSampleCount {
            if i >= 2 {
                let idx0 = (i - 2) % _velocitySamples.count;
                let idx1 = (i - 1) % _velocitySamples.count;
                let v0 = _velocitySamples[idx0];
                let v1 = _velocitySamples[idx1];
                acceleration += (v1 - v0) / _dtSamples[idx1];
                n += 1;
            }
            i += 1
        }
        acceleration *= (1.0 / Float(n))
        _accelerationEstimate = acceleration
    }

    private func updateAngularVelocityEstimate() {
        var velocity: Float = 0
        if _totalSampleCount > 0 {
            let populatedSamples = min(Self._numSamples, _totalSampleCount)
            for i in 0..<populatedSamples {
                velocity += _angularVelocitySamples[i]
            }
            velocity *= (1.0 / Float(populatedSamples))
        }
        _angularVelocityEstimate = velocity
    }

    private func degreesRotated(prevForward: Vector3, currentForward: Vector3) -> Float {
        return Vector3.signedAngle(from: prevForward.xzProjected, to: currentForward.xzProjected, axis: .up)
    }
}
