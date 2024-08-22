//
//  SimpleBinaryDecoder.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import Foundation

class SimpleBinaryDecoder {
    private let _data: Data
    private var _idx = Int(0)
    private var _nextTypeIsContainer = false

    var bytesRead: Int {
        return _idx
    }

    func readBytes<T>(to: inout T, count: Int = MemoryLayout<T>.size) throws {
        let end = _idx + count
        if end > _data.count {
            throw SimpleBinaryCodingError.unexpectedEndOfData(end - _data.count)
        }
        withUnsafeMutableBytes(of: &to) { ptr -> Void in
            self._data.copyBytes(to: ptr, from: _idx..<end)
        }
        _idx = end
    }

    func readData() throws -> Data {
        var numBytes = UInt32(0)
        try readBytes(to: &numBytes, count: MemoryLayout<UInt32>.size)
        let start = _idx
        let end = start + Int(numBytes)
        let data = _data.subdata(in: start..<end)
        _idx = end
        return data
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if let serializableType = type as? SimpleBinaryCodable.Type {
            return (try serializableType.read(from: self)) as! T
        }
        return try T.self(from: self)
    }

    init(_ data: Data) {
        _data = data
    }
}

extension SimpleBinaryDecoder: Decoder {
    var codingPath: [any CodingKey] {
        return []
    }

    var userInfo: [CodingUserInfoKey: Any] {
        return [:]
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        _nextTypeIsContainer = true
        return KeyedDecodingContainer(KeyedContainer<Key>(decoder: self))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return UnkeyedContainer(decoder: self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        return UnkeyedContainer(decoder: self)
    }


    struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        var decoder: SimpleBinaryDecoder

        var codingPath: [any CodingKey] {
            return []
        }

        var allKeys: [Key] {
            return []
        }

        func contains(_ key: Key) -> Bool {
            return true
        }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            return try decoder.decode(T.self)
        }

        func decodeIfPresent<T>(_ type: T.Type, forKey key: Key) throws -> T? where T: Decodable {
            throw SimpleBinaryCodingError.unimplementedDecodingOperation("Optional value within keyed container")
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            throw SimpleBinaryCodingError.unimplementedDecodingOperation("Nil within keyed container")
        }

        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            throw SimpleBinaryCodingError.unimplementedDecodingOperation("Nested keyed container within keyed container")
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            throw SimpleBinaryCodingError.unimplementedDecodingOperation("Nested unkeyed container within keyed container")
        }

        func superDecoder() throws -> any Decoder {
            return decoder
        }

        func superDecoder(forKey key: Key) throws -> any Decoder {
            return decoder
        }
    }
}

fileprivate struct UnkeyedContainer: UnkeyedDecodingContainer, SingleValueDecodingContainer {
    var decoder: SimpleBinaryDecoder

    var codingPath: [any CodingKey] {
        return []
    }

    var count: Int? {
        return nil
    }

    var currentIndex: Int {
        return 0
    }

    var isAtEnd: Bool {
        return false
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        // Unlike encoder case, this *does* occur when decoding individual collection (e.g., Array
        // or Dictionary) elements as individual items, which invokes the singleValuedContainer()
        // method
        return try decoder.decode(type)
    }

    func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T: Decodable {
        throw SimpleBinaryCodingError.unimplementedDecodingOperation("Optional value within unkeyed container")
    }

    func decodeNil() -> Bool {
        fatalError("Unimplemented operation while decoding unkeyed container: decodeNil()")
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        throw SimpleBinaryCodingError.unimplementedDecodingOperation("Nested keyed container within unkeyed container")
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw SimpleBinaryCodingError.unimplementedDecodingOperation("Nested unkeyed container within unkeyed container")
    }

    func superDecoder() throws -> any Decoder {
        return decoder
    }
}
