//
//  PID.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/24/24.
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
