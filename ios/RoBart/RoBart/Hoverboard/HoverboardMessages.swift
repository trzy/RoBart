//
//  HoverboardMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

enum HoverboardMessageID: UInt8 {
    case motorMessage = 0x10
}

struct HoverboardMotorMessage: SimpleBinaryMessage {
    static let id = HoverboardMessageID.motorMessage.rawValue
    var leftMotorThrottle: Float
    var rightMotorThrottle: Float
}
