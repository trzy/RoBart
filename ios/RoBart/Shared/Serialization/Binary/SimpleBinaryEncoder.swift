//
//  SimpleBinaryEncoder.swift
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

class SimpleBinaryEncoder {
    private(set) var data = Data()

    func append<T>(_ buffer: UnsafeBufferPointer<T>) {
        data.append(buffer)
    }

    func write(_ data: Data) {
        var numBytes = UInt32(data.count)
        withUnsafePointer(to: &numBytes) { pointer in
            append(UnsafeBufferPointer(start: pointer, count: 1))
        }
        self.data.append(data)
    }

    static func encode(_ value: Encodable) throws -> Data {
        let encoder = SimpleBinaryEncoder()
        try value.encode(to: encoder)
        return encoder.data
    }

    func encode<T>(_ encodable: T) throws where T: Encodable {
        if let serializableThing = encodable as? SimpleBinaryCodable {
            try serializableThing.write(to: self)
        } else {
            try encodable.encode(to: self)
        }
    }
}

extension SimpleBinaryEncoder: Encoder {
    var codingPath: [any CodingKey] {
        return []
    }

    var userInfo: [CodingUserInfoKey: Any] {
        return [:]
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        return KeyedEncodingContainer(KeyedContainer<Key>(encoder: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        return UnkeyedContainer(encoder: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        return UnkeyedContainer(encoder: self)
    }

    private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        private var _encoder: SimpleBinaryEncoder

        var codingPath: [any CodingKey] {
            return []
        }

        func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
            try _encoder.encode(value)
        }

        func encodeIfPresent<T>(_ value: T?, forKey key: Key) throws where T: Encodable {
            throw SimpleBinaryCodingError.unimplementedEncodingOperation("Optional value within keyed container")
        }

        func encodeNil(forKey key: Key) throws {
            throw SimpleBinaryCodingError.unimplementedEncodingOperation("Nil within keyed container")
        }

        func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            return _encoder.container(keyedBy: keyType)
        }

        func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            return _encoder.unkeyedContainer()
        }

        func superEncoder() -> any Encoder {
            return _encoder
        }

        func superEncoder(forKey key: Key) -> any Encoder {
            return _encoder
        }

        init(encoder: SimpleBinaryEncoder) {
            _encoder = encoder
        }
    }
}

fileprivate struct UnkeyedContainer: UnkeyedEncodingContainer, SingleValueEncodingContainer {
    private var _encoder: SimpleBinaryEncoder

    var codingPath: [any CodingKey] {
        return []
    }

    var count: Int {
        return 0
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        return _encoder.container(keyedBy: keyType)
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        fatalError("Unimplemented operation while encoding unkeyed container: nestedUnkeyedContainer()")
    }

    func encodeNil() throws {
        throw SimpleBinaryCodingError.unimplementedEncodingOperation("Nil within unkeyed container")
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        // If we got here, Swift encoder didn't recognize this or its parent container as one of
        // our supported types and is trying to encode it in an unkeyed or single-value container
        throw SimpleBinaryCodingError.notSimpleBinaryEncodable(T.self)
    }

    func encodeIfPresent<T>(_ value: T?) throws where T: Encodable {
        throw SimpleBinaryCodingError.unimplementedEncodingOperation("Optional value within unkeyed container")
    }

    func superEncoder() -> any Encoder {
        return _encoder
    }

    init(encoder: SimpleBinaryEncoder) {
        _encoder = encoder
    }
}
