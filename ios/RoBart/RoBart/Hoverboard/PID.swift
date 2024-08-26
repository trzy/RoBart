//
//  PID.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/24/24.
//

import Foundation

class PID {
    struct Gains {
        let Kp: Float
        let Ki: Float
        let Kd: Float
    }

    var gains = Gains(Kp: 0, Ki: 0, Kd: 0)
    private(set) var output: Float = 0

    private var _prevError: Float?
    private var _integralError: Float = 0

    init(gains: Gains = Gains(Kp: 0, Ki: 0, Kd: 0)) {
        self.gains = gains
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
        output = self.gains.Kp * error + self.gains.Ki * _integralError + self.gains.Kd * derivativeError
        return output
    }
}
