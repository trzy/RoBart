//
//  Actions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/19/24.
//

import Foundation

struct MoveAction: Codable {
    let distance: Float
}

struct MoveToCellAction: Codable {
    let cellX: Int
    let cellY: Int
}

struct TurnInPlaceAction: Codable {
    let degrees: Float
}

struct FaceTowardCellAction: Codable {
    let cellX: Int
    let cellY: Int
}

struct FaceTowardHeadingAction: Codable {
    let headingDegrees: Float
}

struct Scan360Action: Codable {
}

struct TakePhotoAction: Codable {
}

enum Action: Decodable {
    case move(MoveAction)
    case moveToCell(MoveToCellAction)
    case turnInPlace(TurnInPlaceAction)
    case faceTowardCell(FaceTowardCellAction)
    case faceTowardHeading(FaceTowardHeadingAction)
    case scan360(Scan360Action)
    case takePhoto(TakePhotoAction)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ObjectType: String, Codable {
        case move = "move"
        case moveToCell = "moveToCell"
        case turnInPlace = "turnInPlace"
        case faceTowardCell = "faceTowardCell"
        case faceTowardHeading = "faceTowardHeading"
        case scan360 = "scan360"
        case takePhoto = "takePhoto"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ObjectType.self, forKey: .type)

        // Decode based on the "type" field
        switch type {
        case .move:
            let action = try MoveAction(from: decoder)
            self = .move(action)
        case .moveToCell:
            let action = try MoveToCellAction(from: decoder)
            self = .moveToCell(action)
        case .turnInPlace:
            let action = try TurnInPlaceAction(from: decoder)
            self = .turnInPlace(action)
        case .faceTowardCell:
            let action = try FaceTowardCellAction(from: decoder)
            self = .faceTowardCell(action)
        case .faceTowardHeading:
            let action = try FaceTowardHeadingAction(from: decoder)
            self = .faceTowardHeading(action)
        case .scan360:
            let action = try Scan360Action(from: decoder)
            self = .scan360(action)
        case .takePhoto:
            let action = try TakePhotoAction(from: decoder)
            self = .takePhoto(action)
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
