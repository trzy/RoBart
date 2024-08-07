//
//  Messages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

enum MotorMessageID: UInt8 {
    case motorMessage = 0x10
}

struct MotorMessage: SimpleBinaryMessage {
    static let id = MotorMessageID.motorMessage.rawValue
    var leftMotorThrottle: Float
    var rightMotorThrottle: Float
}
