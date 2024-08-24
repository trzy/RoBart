//
//  HoverboardMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

enum HoverboardMessageID: UInt8 {
    case pingMessage = 0x01
    case pongMessage = 0x02
    case configMessage = 0x03
    case motorMessage = 0x10
}

struct HoverboardPingMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.pingMessage.rawValue
    let timestamp: Double
}

struct HoverboardPongMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.pongMessage.rawValue
    let timestamp: Double   // timestamp from ping message (useful for measuring RTT)
}

struct HoverboardConfigMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.configMessage.rawValue
    let watchdogEnabled: Bool
    let watchdogSeconds: Double
}

struct HoverboardMotorMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.motorMessage.rawValue
    let leftMotorThrottle: Float
    let rightMotorThrottle: Float
}
