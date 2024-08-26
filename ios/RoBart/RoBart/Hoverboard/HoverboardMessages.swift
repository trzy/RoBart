//
//  HoverboardMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

enum HoverboardMessageID: UInt32 {
    case pingMessage = 0x01
    case pongMessage = 0x02
    case watchdogMessage = 0x03
    case pwmMessage = 0x04
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

struct HoverboardWatchdogMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.watchdogMessage.rawValue
    let watchdogEnabled: Bool
    let watchdogSeconds: Double
}

struct HoverboardPWMMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.pwmMessage.rawValue
    let pwmFrequency: UInt16
}

struct HoverboardMotorMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.motorMessage.rawValue
    let leftMotorThrottle: Float
    let rightMotorThrottle: Float
}
