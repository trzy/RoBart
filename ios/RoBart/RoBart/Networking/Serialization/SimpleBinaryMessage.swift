//
//  SimpleBinaryMessage.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
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
    let numBytes: UInt8
    let id: UInt8

    static var headerSize: UInt32 {
        return UInt32(MemoryLayout<UInt8>.size * 2)
    }

    var bodySize: UInt32 {
        return UInt32(numBytes) - Self.headerSize
    }

    static func extractHeaderAndBody(from data: Data) -> (header: Header, body: Data) {
        do {
            let header = try Header(from: SimpleBinaryDecoder(data))
            let body = header.bodySize == 0 ? Data() : data.advanced(by: Int(Header.headerSize))
            return (header: header, body: body)
        } catch {
            fatalError("Failed to deserialize header: \(error.localizedDescription)")
        }
    }

    static func deserialize(from data: Data) -> Header {
        do {
            return try Header(from: SimpleBinaryDecoder(data))
        } catch  {
            fatalError("Failed to deserialize header: \(error.localizedDescription)")
        }
    }

    init?(bodySize: Int, id: UInt8) {
        guard let numBytes = UInt8(exactly: bodySize + Int(Header.headerSize)) else {
            return nil
        }
        self.numBytes = numBytes
        self.id = id
    }
}

protocol SimpleBinaryMessage: Codable {
    static var id: UInt8 {
        get
    }

    func serialize() -> Data
}

extension SimpleBinaryMessage {
    func serialize() -> Data {
        do {
            let encoder = SimpleBinaryEncoder()
            try UInt8(0).write(to: encoder) // header: size is a placeholder for now, will be patched
            try Self.id.write(to: encoder)  // header: message ID
            try encoder.encode(self)        // body
            var encodedData = encoder.data
            guard let numBytes = UInt8(exactly: encodedData.count) else {
                fatalError("Failed to serialize message because its size (\(encodedData.count) bytes) exceeds maximum message size of 255 bytes")
            }
            encodedData[0] = numBytes       // patch total message size into header
            return encodedData
        } catch {
            fatalError("Failed to serialize message (id=\(String(format: "0x%02x", Self.id))): \(error.localizedDescription)")
        }
    }

    static func deserialize(from data: Data) -> Self {
        let (header, body) = Header.extractHeaderAndBody(from: data)
        return Self.deserialize(header: header, body: body)
    }

    static fileprivate func deserialize(header: Header, body: Data) -> Self {
        do {
            if header.id != Self.id {
                fatalError("Cannot deserialize message of id=\(String(format: "0x%02x", Self.id)) because its header contains id=\(header.id)")
            }
            return try Self.self(from: SimpleBinaryDecoder(body))
        } catch {
            fatalError("Failed to deserialize message (id=\(String(format: "0x%02x", Self.id))): \(error.localizedDescription)")
        }
    }
}
