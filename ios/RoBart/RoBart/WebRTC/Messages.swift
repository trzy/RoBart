//
//  Messages.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 12/27/25.
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

protocol JSONEncodable: Encodable {
    func toJSON() -> String
}

extension JSONEncodable {
    func toJSON() -> String {
        let json = try! JSONEncoder().encode(self)
        return String(data: json, encoding: .utf8)!
    }
}

struct HelloMessage: Codable, JSONEncodable {
    var type: String { return "HelloMessage" }
    let message: String

    enum CodingKeys: String, CodingKey {
        case type, message
    }

    init(message: String) {
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(message, forKey: .message)
    }
}

struct ReadyToConnectMessage: Codable, JSONEncodable {
    var type: String { return "ReadyToConnectMessage" }

    enum CodingKeys: String, CodingKey {
        case type
    }

    init() {
    }

    init(from decoder: Decoder) throws {
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
    }
}


struct RoleMessage: Codable, JSONEncodable {
    var type: String { return "RoleMessage" }
    let role: String

    enum CodingKeys: String, CodingKey {
        case type, role
    }

    init(role: String) {
        self.role = role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(role, forKey: .role)
    }
}

struct ICECandidateMessage: Codable, JSONEncodable {
    var type: String { return "ICECandidateMessage" }
    let data: String

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(data: String) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(String.self, forKey: .data)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
    }
}

struct OfferMessage: Codable, JSONEncodable {
    var type: String { return "OfferMessage" }
    let data: String

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(data: String) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(String.self, forKey: .data)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
    }
}

struct AnswerMessage: Codable, JSONEncodable {
    var type: String { return "AnswerMessage" }
    let data: String

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(data: String) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(String.self, forKey: .data)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
    }
}

enum Message: Decodable {
    case hello(HelloMessage)
    case readyToConnect(ReadyToConnectMessage)
    case role(RoleMessage)
    case iceCandidate(ICECandidateMessage)
    case offer(OfferMessage)
    case answer(AnswerMessage)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum ObjectType: String, Codable {
        case hello = "HelloMessage"
        case readyToConnect = "ReadyToConnect"
        case role = "RoleMessage"
        case iceCandidate = "ICECandidateMessage"
        case offer = "OfferMessage"
        case answer = "AnswerMessage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ObjectType.self, forKey: .type)
        switch type {
        case .hello:
            let msg = try HelloMessage(from: decoder)
            self = .hello(msg)
        case .readyToConnect:
            let msg = try ReadyToConnectMessage(from: decoder)
            self = .readyToConnect(msg)
        case .role:
            let msg = try RoleMessage(from: decoder)
            self = .role(msg)
        case .iceCandidate:
            let msg = try ICECandidateMessage(from: decoder)
            self = .iceCandidate(msg)
        case .offer:
            let msg = try OfferMessage(from: decoder)
            self = .offer(msg)
        case .answer:
            let msg = try AnswerMessage(from: decoder)
            self = .answer(msg)
        }
    }

    static func decode(from json: String) -> Message? {
        guard let jsonData = json.data(using: .utf8) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Message.self, from: jsonData)
        } catch {
            print("[Message] Error: Unable to decode JSON: \(error.localizedDescription)")
        }
        return nil
    }
}
