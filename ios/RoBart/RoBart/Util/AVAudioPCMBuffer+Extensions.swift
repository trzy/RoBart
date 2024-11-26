//
//  AVAudioPCMBuffer+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/26/24.
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

import AVFoundation

extension AVAudioPCMBuffer {
    static func fromData(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            log("Error: Failed to create AVAudioPCMBuffer")
            return nil
        }

        buffer.frameLength = frameCount
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers

        data.withUnsafeBytes { (bufferPointer) in
            guard let address = bufferPointer.baseAddress else {
                log("Error: Failed to get base address of data")
                return
            }
            audioBuffer.mData?.copyMemory(from: address, byteCount: Int(audioBuffer.mDataByteSize))
        }

        return buffer
    }
}

fileprivate func log(_ message: String) {
    print("[AVAudioPCMBuffer] \(message)")
}
