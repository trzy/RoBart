//
//  ServerMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/21/24.
//
//  Messages sent between debug server and iPhone.
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

struct RequestOccupancyMapMessage: JSONMessage {
    let unused: Bool    // Python side doesn't support empty messages so create a dummy field
}

struct OccupancyMapMessage: JSONMessage {
    let cellsWide: Int
    let cellsDeep: Int
    let occupancy: [Float]
    let robotCell: [Int]    // 2 elements: x, z
}

struct DrivePathMessage: JSONMessage {
    let pathCells: [[Int]]  // array of [cellX, cellZ]
}

struct RequestAnnotatedViewMessage: JSONMessage {
    let unused: Bool
}

struct AnnotatedViewMessage: JSONMessage {
    let imageBase64: String
}
