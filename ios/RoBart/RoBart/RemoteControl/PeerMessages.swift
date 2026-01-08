//
//  PeerMessages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//
//  Messages sent between iPhones using Multipeer Connectivity.
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

enum PeerMessageID: UInt32 {
    case roleMessage = 0x80
    case collaborationMessage = 0x81
    case motorMessage = 0x82
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
