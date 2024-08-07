//
//  MotionEstimator.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import ARKit

class MotionEstimator {
    private static let _numSamples = 5
    private var _velocitySamples = Array(repeating: Vector3.zero, count: _numSamples)
    private var _dtSamples = Array(repeating: Float.zero, count: _numSamples)
    private var _prevPosition: Vector3?
    private var _prevFrameTime: TimeInterval = 0
    private var _velocityEstimate = Vector3.zero
    private var _prevVelocityEstimate = Vector3.zero
    private var _accelerationEstimate = Vector3.zero
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

    func update(_ frame: ARFrame) {
        let currentPosition = ARSessionManager.shared.transform.position
        let currentTime = frame.timestamp

        if let prevPosition = _prevPosition {
            let dt = Float(currentTime - _prevFrameTime)
            let idx = _totalSampleCount % Self._numSamples
            _velocitySamples[idx] = (currentPosition - prevPosition) / dt
            _dtSamples[idx] = dt
            _totalSampleCount += 1
        }

        _prevPosition = currentPosition
        _prevFrameTime = currentTime

        updateVelocityEstimate()
        updateAccelerationEstimate()

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
}
