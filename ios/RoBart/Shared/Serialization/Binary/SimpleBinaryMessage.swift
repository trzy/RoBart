//
//  SimpleBinaryMessage.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
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

//
//  Simple sequentially-encoded binary messages. Keyed formats not supported, although
//  Dictionary<T> works as long as both keys and values are SimpleBinaryCodable.
//
//  Notes
//  -----
//  - Keyed coding is not supported. Keys are ignored and any attempt to decode based on a key will
//    always appear to return true.
//
//  - Do not write custom encode() or init(from: decoder) functions as they will break the
//    semantics of the system.
//
//  - Optionals are not implemented yet.
//
//  - Enums will work but must explicitly be declared Codable, SimpleBinaryCodable, and have a raw
//    representable type (the enum type) that is also Codable and SimpleBinaryCodable. Example:
//
//      enum MyEnum: Int, SimpleBinaryCodable, Codable {
//          case optionA
//          case optionB
//      }
//
//  - Initialized constant struct fields ("let") will be encoded but will crash on decode as the
//    the decoding process silently skips over them. For example:
//
//      struct MyType: Codable {
//          let foo = 5
//          var bar = 6
//      }
//
//    Field bar is fine but foo will only be encoded and never decoded. There seems to be no way to
//    detect this situation and it affects Codables in general. See:
//    https://forums.swift.org/t/revisit-synthesized-init-from-decoder-for-structs-with-default-property-values/12296/7
//
//  - Avoid directly encoding or decoding types that are not classes or structs.
//    SimpleBinaryEncoder and SimpleBinaryDecoder assume they will be iterating a keyed container
//    and will forward handling of any unknown sub-container (a Dictionary field or an Array, for
//    example) to SimpleBinaryCodable.write() and .read(). Do not try to use them on anything other
//    than SimpleBinaryMessage structs and classes.
//

import Foundation

fileprivate struct Header: Codable {
    let numBytes: UInt32
    let id: UInt32

    static var headerSize: UInt32 {
        return UInt32(MemoryLayout<UInt8>.size * 8)
    }

    var bodySize: UInt32 {
        return UInt32(numBytes) - Self.headerSize
    }

    static func extractHeaderAndBody(from data: Data) throws -> (header: Header, body: Data) {
        let header = try Header(from: SimpleBinaryDecoder(data))
        let body = header.bodySize == 0 ? Data() : data.advanced(by: Int(Header.headerSize))
        return (header: header, body: body)
    }

    static func deserialize(from data: Data) -> Header {
        do {
            return try Header(from: SimpleBinaryDecoder(data))
        } catch  {
            fatalError("Failed to deserialize header: \(error.localizedDescription)")
        }
    }

    init?(bodySize: UInt32, id: UInt32) {
        guard let numBytes = UInt32(exactly: bodySize + Header.headerSize) else {
            return nil
        }
        self.numBytes = numBytes
        self.id = id
    }
}

protocol SimpleBinaryMessage: Codable {
    static var id: UInt32 {
        get
    }

    func serialize() -> Data
}

extension SimpleBinaryMessage {
    func serialize() -> Data {
        do {
            let encoder = SimpleBinaryEncoder()
            try UInt32(0).write(to: encoder)    // header: size is a placeholder for now, will be patched
            try Self.id.write(to: encoder)      // header: message ID
            try encoder.encode(self)            // body
            var encodedData = encoder.data
            guard var numBytes = UInt32(exactly: encodedData.count) else {
                fatalError("Failed to serialize message because its size (\(encodedData.count) bytes) exceeds maximum message size")
            }
            encodedData.replaceSubrange(0..<4, with: &numBytes, count: 4)   // patch message size into header
            return encodedData
        } catch {
            fatalError("Failed to serialize message (id=\(String(format: "0x%02x", Self.id))): \(error.localizedDescription)")
        }
    }

    static func deserialize(from data: Data) -> Self? {
        do {
            let (header, body) = try Header.extractHeaderAndBody(from: data)
            return Self.deserialize(header: header, body: body)
        } catch {
            return nil
        }
    }

    static fileprivate func deserialize(header: Header, body: Data) -> Self? {
        do {
            if header.id != Self.id {
                return nil
            }
            return try Self.self(from: SimpleBinaryDecoder(body))
        } catch {
            return nil
        }
    }
}
