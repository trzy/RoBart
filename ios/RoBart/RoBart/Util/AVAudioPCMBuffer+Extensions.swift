//
//  AVAudioPCMBuffer+Extensions.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/26/24.
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
