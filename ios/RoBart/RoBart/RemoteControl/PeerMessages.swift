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
}

struct PeerRoleMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.roleMessage.rawValue
    let role: Role
}

struct PeerCollaborationMessage: SimpleBinaryMessage {
    static let id = PeerMessageID.collaborationMessage.rawValue
    let data: Data
}