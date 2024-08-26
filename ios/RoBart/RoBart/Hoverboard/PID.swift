//
//  PID.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/24/24.
//

import Foundation

class PID {
    var Kp: Float = 0 {
        didSet {
            reset()
        }
    }

    var Ki: Float = 0 {
        didSet {
            reset()
        }
    }

    var Kd: Float = 0 {
        didSet {
            reset()
        }
    }

    private(set) var output: Float = 0

    private var _prevError: Float?
    private var _integralError: Float = 0

    init(Kp: Float = 0, Ki: Float = 0, Kd: Float = 0) {
        self.Kp = Kp
        self.Ki = Ki
        self.Kd = Kd
    }

    func reset() {
        _prevError = nil
        _integralError = 0
        output = 0
    }

    func update(deltaTime dt: Float, error: Float) -> Float {
        if _prevError == nil {
            _prevError = error
        }
        _integralError = _integralError + dt * error
        let derivativeError = (error - _prevError!) / dt
        output = Kp * error + Ki * _integralError + Kd * derivativeError
        return output
    }
}
