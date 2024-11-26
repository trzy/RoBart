//
//  SimpleBinaryCodingError.swift
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

import Foundation

enum SimpleBinaryCodingError: Swift.Error {
    /// Type is `Decodable` but not `SimpleBinaryCodable`. `SimpleBinaryCodable` is required
    /// because `SimpleBinaryDecoder` lacks support for full keyed coding.
    case notSimpleBinaryDecodable(Decodable.Type)

    /// Type is `Encodable` but not `SimpleBinaryCodable`. `SimpleBinaryCodable` is required
    /// because `SimpleBinaryEncoder` lacks support for full keyed coding.
    case notSimpleBinaryEncodable(Encodable.Type)

    /// Type is not `Decodable`.
    case notDecodable(Any.Type)

    /// Decoder encountered end of data prematurely (while decoding values that require more).
    case unexpectedEndOfData(Int)

    /// Cannot decode `Int` because it cannot be represented. This happens in 32-bit code because
    /// `Int` is serialized as a 64-bit value and may not fit within 32 bits when deserialized.
    case intOutOfRange(Int64)

    /// Cannot decode `UInt` because it cannot be represented. This happens in 32-bit code because
    /// `UInt` is serialized as a 64-bit value and may not fit within 32 bits when deserialized.
    case uintOutOfRange(UInt64)

    /// Cannot decode `String` because it is not UTF-8 encoded.
    case invalidUTF8([UInt8])

    /// Raw value found during decoding is nto valid for the type being decoded.
    case invalidValueForRawRepresentable

    /// Encoder tried to perform an unimplemented operation.
    case unimplementedEncodingOperation(String)

    /// Decoding tried to perform an unimplemented operation.
    case unimplementedDecodingOperation(String)
}

extension SimpleBinaryCodingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notSimpleBinaryDecodable(let type):
            if type is SimpleBinaryCodable.Type {
                return "Type exists within a container that is Decodable but not SimpleBinaryCodable: \(type)"
            } else {
                return "Type is Decodable but not SimpleBinaryCodable: \(type)"
            }
        case .notSimpleBinaryEncodable(let type):
            if type is SimpleBinaryCodable.Type {
                return "Type exists within a container that is Encodable but not SimpleBinaryCodable: \(type)"
            } else {
                return "Type is Encodable but not SimpleBinaryCodable: \(type)"
            }
        case .notDecodable(let type):
            return "Type is not Decodable: \(type)"
        case .unexpectedEndOfData(let expectedNumBytes):
            return "Expected \(expectedNumBytes) more \(expectedNumBytes == 1 ? "byte" : "bytes") but data buffer ended prematurely"
        case .intOutOfRange(let value):
            return "Signed integer (0x\(String(format: "%x", value))) cannot be decoded on this platform because it exceeds 32 bits"
        case .uintOutOfRange(let value):
            return "Unsigned integer (0x\(String(format: "%x", value))) cannot be decoded on this platform because it exceeds 32 bits"
        case .invalidUTF8(let data):
            return "Cannot decode \(data.count)-byte string because it is not valid UTF-8"
        case .invalidValueForRawRepresentable:
            return "Encoded value is not valid for the raw representable type being decoded"
        case .unimplementedEncodingOperation(let message):
            return "Encoding not implemented: \(message)"
        case .unimplementedDecodingOperation(let message):
            return "Decoding not implemented: \(message)"
        }
    }
}
