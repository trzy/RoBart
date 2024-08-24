//
//  ServerMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/21/24.
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

struct DriveForDurationMessage: JSONMessage {
    let reverse: Bool
    let seconds: Float
    let speed: Float
}

struct DriveForDistanceMessage: JSONMessage {
    let reverse: Bool
    let meters: Float
    let speed: Float
}

struct WatchdogSettingsMessage: JSONMessage {
    let enabled: Bool
    let timeoutSeconds: Double
}

struct HoverboardRTTMeasurementMessage: JSONMessage {
    let numSamples: Int         // number of samples to take
    let delay: Double           // seconds to sleep between consecutive samples
    let rttSeconds: [Double]    // resulting times (sent back as response)
}
