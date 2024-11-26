//
//  Actions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/19/24.
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

struct MoveAction: Codable {
    let distance: Float
}

struct MoveToAction: Codable {
    let pointNumber: Int
}

struct TurnInPlaceAction: Codable {
    let degrees: Float
}

struct FaceTowardAction: Codable {
    let pointNumber: Int
}

struct FaceTowardHeadingAction: Codable {
    let headingDegrees: Float
}

struct Scan360Action: Codable {
}

struct TakePhotoAction: Codable {
}

struct BackOutAction: Codable {
}

struct FollowHumanAction: Codable {
    var seconds: Double?
    var distance: Float?
}

enum Action: Decodable {
    case move(MoveAction)
    case moveTo(MoveToAction)
    case turnInPlace(TurnInPlaceAction)
    case faceToward(FaceTowardAction)
    case faceTowardHeading(FaceTowardHeadingAction)
    case scan360(Scan360Action)
    case takePhoto(TakePhotoAction)
    case backOut(BackOutAction)
    case followHuman(FollowHumanAction)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ObjectType: String, Codable {
        case move = "move"
        case moveTo = "moveTo"
        case turnInPlace = "turnInPlace"
        case faceToward = "faceToward"
        case faceTowardHeading = "faceTowardHeading"
        case scan360 = "scan360"
        case takePhoto = "takePhoto"
        case backOut = "backOut"
        case followHuman = "followHuman"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ObjectType.self, forKey: .type)

        // Decode based on the "type" field
        switch type {
        case .move:
            let action = try MoveAction(from: decoder)
            self = .move(action)
        case .moveTo:
            let action = try MoveToAction(from: decoder)
            self = .moveTo(action)
        case .turnInPlace:
            let action = try TurnInPlaceAction(from: decoder)
            self = .turnInPlace(action)
        case .faceToward:
            let action = try FaceTowardAction(from: decoder)
            self = .faceToward(action)
        case .faceTowardHeading:
            let action = try FaceTowardHeadingAction(from: decoder)
            self = .faceTowardHeading(action)
        case .scan360:
            let action = try Scan360Action(from: decoder)
            self = .scan360(action)
        case .takePhoto:
            let action = try TakePhotoAction(from: decoder)
            self = .takePhoto(action)
        case .backOut:
            let action = try BackOutAction(from: decoder)
            self = .backOut(action)
        case .followHuman:
            let action = try FollowHumanAction(from: decoder)
            self = .followHuman(action)
        }
    }
}

func decodeActions(from json: String) -> [Action]? {
    guard let jsonData = json.data(using: .utf8) else { return nil }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode([Action].self, from: jsonData)
    } catch {
        print("[Actions] Error decoding JSON: \(error)")
    }

    return nil
}
