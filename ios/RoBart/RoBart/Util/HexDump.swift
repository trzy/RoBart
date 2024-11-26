//
//  HexDump.swift
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

extension Util {
    /// Prints a hexadecimal dump of data to the console. Each line of output contains the offset within the buffer, the hex bytes, and the ASCII interpretation.
    ///
    /// - Parameters
    ///     - data: Buffer to dump.
    ///     - bytesPerLine: How many bytes per line to print.
    ///     - offsetBytes: How many bytes to use for the offset field (1-8). The offset will be truncated to fit. For example, a value of 3 would cover 000000-ffffff.
    public static func hexDump(_ data: Data, bytesPerLine: Int = 16, offsetBytes: Int = 2) {
        let offsetBytes = max(min(offsetBytes, 8), 1)   // clamp offsetBytes to 1...8 (8 to 64 bits)
        let maskLUT: [UInt64] = [ 0xff, 0xffff, 0xffffff, 0xffffffff, 0xffffffffff, 0xffffffffffff, 0xffffffffffffff, 0xffffffffffffffff ]
        let offsetMask = maskLUT[offsetBytes - 1]
        let offsetFormat = String(format: "%%0%dx", offsetBytes * 2)
        var start: UInt64 = 0
        while start < data.count {
            let end = min(start + UInt64(bytesPerLine), UInt64(data.count))
            let hex = data[start..<end].map({ String(format: "%02x", $0) }).joined(separator: " ")
            let ascii = data[start..<end].map({ isprint(Int32($0)) != 0 ? Character(UnicodeScalar($0)) : Character(".") })
            let readable = String(ascii)
            let offset = String(format: offsetFormat, start & offsetMask)
            let expectedHexLength = 3 * bytesPerLine    // "%02x " <-- 3 chars
            let hexPadding = String(repeating: " ", count: expectedHexLength - hex.count)
            let asciiPadding = String(repeating: " ", count: bytesPerLine - ascii.count)
            print(String(format: "%@: %@%@ %@%@", offset, hex, hexPadding, readable, asciiPadding))
            start = end
        }
    }
}
