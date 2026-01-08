//
//  ServerMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/21/24.
//
//  Messages sent between debug server and iPhone.
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

/// Sent by both sides on connect. Useful for testing.
struct HelloMessage: JSONMessage {
    let message: String
}

/// Sent by iOS to server to log a message.
struct LogMessage: JSONMessage {
    let text: String
}

// Open loop
struct DriveForDurationMessage: JSONMessage {
    let reverse: Bool
    let seconds: Float
    let speed: Float
}

// Open loop
struct DriveForDistanceMessage: JSONMessage {
    let reverse: Bool
    let meters: Float   // unsigned
    let speed: Float
}

// PID control
struct RotateMessage: JSONMessage {
    let degrees: Float
}

// PID control
struct DriveForwardMessage: JSONMessage {
    let deltaMeters: Float  // signed
}

struct WatchdogSettingsMessage: JSONMessage {
    let enabled: Bool
    let timeoutSeconds: Double
}

struct PWMSettingsMessage: JSONMessage {
    let pwmFrequency: Int
}

struct ThrottleMessage: JSONMessage {
    let maxThrottle: Float
}

struct PIDGainsMessage: JSONMessage {
    let whichPID: String
    let Kp: Float
    let Ki: Float
    let Kd: Float
}

struct HoverboardRTTMeasurementMessage: JSONMessage {
    let numSamples: Int         // number of samples to take
    let delay: Double           // seconds to sleep between consecutive samples
    let rttSeconds: [Double]    // resulting times (sent back as response)
}

struct AngularVelocityMeasurementMessage: JSONMessage {
    let steering: Float
    let numSeconds: Double
    let angularVelocityResult: Float
}

struct PositionGoalToleranceMessage: JSONMessage {
    let positionGoalTolerance: Float
}

struct RenderSceneGeometryMessage: JSONMessage {
    let planes: Bool
    let meshes: Bool
}
