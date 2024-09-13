//
//  PeerMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//
//  Messages sent between iPhones using Multipeer Connectivity.
//

import Foundation

enum PeerMessageID: UInt32 {
    case roleMessage = 0x80
    case collaborationMessage = 0x81
    case motorMessage = 0x82
    case stopMessage = 0x83
    case occupancyMessage = 0x84
}

struct PeerRoleMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.roleMessage.rawValue
    let role: Role
}

struct PeerCollaborationMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.collaborationMessage.rawValue
    let data: Data
}

struct PeerMotorMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.motorMessage.rawValue
    let leftMotorThrottle: Float
    let rightMotorThrottle: Float
}

struct PeerStopMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.stopMessage.rawValue
}

struct PeerOccupancyMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.occupancyMessage.rawValue
    let width: Float
    let depth: Float
    let cellWidth: Float
    let cellDepth: Float
    let centerPoint: Vector3
    let occupancy: [Float]
    let path: [Vector3]
    let ourTransform: Matrix4x4
}
