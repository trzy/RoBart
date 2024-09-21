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

struct MoveToAction: Codable {
    let positionNumber: Int
}

struct TurnInPlaceAction: Codable {
    let degrees: Float
}

struct FaceTowardPhotoAction: Codable {
    let photoName: String
}

struct FaceTowardPointAction: Codable {
    let positionNumber: Int
}

struct FaceTowardHeadingAction: Codable {
    let headingDegrees: Float
}

struct TakePhotoAction: Codable {
}

enum Action: Decodable {
    case move(MoveAction)
    case moveTo(MoveToAction)
    case turnInPlace(TurnInPlaceAction)
    case faceTowardPhoto(FaceTowardPhotoAction)
    case faceTowardPoint(FaceTowardPointAction)
    case faceTowardHeading(FaceTowardHeadingAction)
    case takePhoto(TakePhotoAction)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ObjectType: String, Codable {
        case move = "move"
        case moveTo = "moveTo"
        case turnInPlace = "turnInPlace"
        case faceTowardPhoto = "faceTowardPhoto"
        case faceTowardPoint = "faceTowardPoint"
        case faceTowardHeading = "faceTowardHeading"
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
        case .moveTo:
            let action = try MoveToAction(from: decoder)
            self = .moveTo(action)
        case .turnInPlace:
            let action = try TurnInPlaceAction(from: decoder)
            self = .turnInPlace(action)
        case .faceTowardPhoto:
            let action = try FaceTowardPhotoAction(from: decoder)
            self = .faceTowardPhoto(action)
        case .faceTowardPoint:
            let action = try FaceTowardPointAction(from: decoder)
            self = .faceTowardPoint(action)
        case .faceTowardHeading:
            let action = try FaceTowardHeadingAction(from: decoder)
            self = .faceTowardHeading(action)
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
