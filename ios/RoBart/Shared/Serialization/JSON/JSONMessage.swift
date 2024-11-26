//
//  JSONMessage.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/21/24.
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

struct ReceivedJSONMessage {
    let id: String
    let jsonData: Data
}

fileprivate struct IDField: Decodable {
    let __id: String
}

protocol JSONMessage: Codable {
}

fileprivate let _decoder = JSONDecoder()

extension JSONMessage {
    static var id: String {
        return String(describing: Self.self)
    }

    func serialize() -> Data {
        do {
            // Encode as JSON and replace the final '}' with ',"__id":"ClassName"}'
            var jsonData = try JSONEncoder().encode(self)
            if jsonData.count >= 2 && jsonData[jsonData.count - 1] == Character("}").asciiValue! {
                if let extraData = "\"__id\":\"\(Self.id)\"}".data(using: .utf8) {
                    // If JSON is just {}, do not replace end bracket with ,
                    jsonData[jsonData.count - 1] = jsonData.count == 2 ? Character(" ").asciiValue! : Character(",").asciiValue!
                    jsonData.append(extraData)
                }
            }

            // Add 4 byte size header
            if var totalSize = UInt32(exactly: 4 + jsonData.count) {
                var data = Data(capacity: Int(totalSize))
                withUnsafePointer(to: &totalSize) {
                    data.append(UnsafeBufferPointer(start: $0, count: 1))
                }
                data.append(jsonData)
                return data
            }
        } catch {
            log("Serialization failed")
        }

        return Data()
    }

    static func deserialize(_ data: Data) -> ReceivedJSONMessage? {
        let decoder = JSONDecoder()
        do {
            let idField = try decoder.decode(IDField.self, from: data)
            return ReceivedJSONMessage(id: idField.__id, jsonData: data)
        } catch {
            log("Deserialization failed")
            return nil
        }
    }

    static func decode<T>(_ receivedMessage: ReceivedJSONMessage, as type: T.Type) -> T? where T: JSONMessage {
        return try? _decoder.decode(type.self, from: receivedMessage.jsonData)
    }
}

/// Allows JSONMessage's static deserialize() method to be called. Swift does not permit static
/// methods to be called on the protocol metatype directly, hence this dummy concrete type.
struct JSONMessageDeserializer: JSONMessage {
}

fileprivate func log(_ message: String) {
    print("[JSONMessage] \(message)")
}
