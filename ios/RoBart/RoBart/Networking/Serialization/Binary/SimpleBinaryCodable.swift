//
//  SimpleBinaryCodable.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import Foundation

protocol SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws
    static func read(from reader: SimpleBinaryDecoder) throws -> Self
}

extension Int8: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Int8 {
        var value = Int8(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension UInt8: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> UInt8 {
        var value = UInt8(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension Int16: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Int16 {
        var value = Int16(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension UInt16: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> UInt16 {
        var value = UInt16(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension Int32: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Int32 {
        var value = Int32(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension UInt32: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> UInt32 {
        var value = UInt32(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension Float: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Float {
        var value = Float(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension Double: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value = self
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Double {
        var value = Double(0)
        try reader.readBytes(to: &value)
        return value
    }
}

extension Bool: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        var value: UInt8 = self ? 1 : 0
        withUnsafePointer(to: &value) {
            writer.append(UnsafeBufferPointer(start: $0, count: 1))
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Bool {
        var value = UInt8(0)
        try reader.readBytes(to: &value)
        return value != 0
    }
}

extension Array: SimpleBinaryCodable where Element: Codable {
    func write(to writer: SimpleBinaryEncoder) throws {
        guard let count = UInt32(exactly: self.count) else {
            throw SimpleBinaryCodingError.intOutOfRange(Int64(self.count))
        }
        try count.write(to: writer)
        for element in self {
            try writer.encode(element)
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> [ Element ] {
        let count = try UInt32.read(from: reader)
        var array: [ Element ] = []
        for _ in 0..<count {
            array.append(try reader.decode(Element.self))
        }
        return array
    }
}

extension String: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        let bytes: [UInt8] = Array(self.utf8)
        try bytes.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> String {
        let bytes: [UInt8] = try [UInt8].read(from: reader)
        guard let str = String(bytes: bytes, encoding: .utf8) else {
            throw SimpleBinaryCodingError.invalidUTF8(bytes)
        }
        return str
    }
}

extension Data: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        writer.write(self)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Data {
        return try reader.readData()
    }
}

// Allow enums with raw values that are SimpleBinaryCodable to trivially conform to SimpleBinaryCodable
extension SimpleBinaryCodable where Self: RawRepresentable, RawValue: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        try self.rawValue.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Self {
        try Self(rawValue: .read(from: reader))!
    }
}

extension Dictionary: SimpleBinaryCodable where Key: Codable, Value: Codable {
    func write(to writer: SimpleBinaryEncoder) throws {
        guard let count = UInt32(exactly: self.count) else {
            throw SimpleBinaryCodingError.intOutOfRange(Int64(self.count))
        }
        try count.write(to: writer)
        for (key, value) in self {
            try writer.encode(key)
            try writer.encode(value)
        }
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Dictionary {
        var dict = [Key: Value]()
        let count = try UInt32.read(from: reader)
        for _ in 0..<count {
            let key = try reader.decode(Key.self)
            let value = try reader.decode(Value.self)
            dict[key] = value
        }
        return dict
    }
}

extension Vector3: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        try self.x.write(to: writer)
        try self.y.write(to: writer)
        try self.z.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Vector3 {
        let x = try Float.read(from: reader)
        let y = try Float.read(from: reader)
        let z = try Float.read(from: reader)
        return Vector3(x: x, y: y, z: z)
    }
}

extension Vector4: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        try self.x.write(to: writer)
        try self.y.write(to: writer)
        try self.z.write(to: writer)
        try self.w.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Vector4 {
        let x = try Float.read(from: reader)
        let y = try Float.read(from: reader)
        let z = try Float.read(from: reader)
        let w = try Float.read(from: reader)
        return Vector4(x: x, y: y, z: z, w: w)
    }
}

extension Matrix4x4: SimpleBinaryCodable {
    func write(to writer: SimpleBinaryEncoder) throws {
        try self.columns.0.write(to: writer)
        try self.columns.1.write(to: writer)
        try self.columns.2.write(to: writer)
        try self.columns.3.write(to: writer)
    }

    static func read(from reader: SimpleBinaryDecoder) throws -> Matrix4x4 {
        let column0 = try Vector4.read(from: reader)
        let column1 = try Vector4.read(from: reader)
        let column2 = try Vector4.read(from: reader)
        let column3 = try Vector4.read(from: reader)
        return Matrix4x4(column0, column1, column2, column3)
    }
}
