//
//  AVAudioPCMBuffer+Extensions.swift
//  WebRTCVAD
//
//  Created by Bart Trzynadlowski on 9/16/24.
//

import AVFoundation

extension AVAudioPCMBuffer {
    /// Creates a new copy of the buffer.
    /// - Returns: A copy of the buffer.
    func copy() -> AVAudioPCMBuffer? {
        guard let copyBuffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: self.frameCapacity) else { return nil }

        copyBuffer.frameLength = self.frameLength

        let channelCount = Int(self.format.channelCount)

        if let selfFloatChannelData = self.floatChannelData,
           let copyFloatChannelData = copyBuffer.floatChannelData {
            for channel in 0..<channelCount {
                memcpy(copyFloatChannelData[channel], selfFloatChannelData[channel], Int(self.frameLength) * MemoryLayout<Float>.size)
            }
        }

        if let selfInt16ChannelData = self.int16ChannelData,
           let copyInt16ChannelData = copyBuffer.int16ChannelData {
            for channel in 0..<channelCount {
                memcpy(copyInt16ChannelData[channel], selfInt16ChannelData[channel],Int(self.frameLength) * MemoryLayout<Int16>.size)
            }
        }

        if let selfInt32ChannelData = self.int32ChannelData,
           let copyInt32ChannelData = copyBuffer.int32ChannelData {
            for channel in 0..<channelCount {
                memcpy(copyInt32ChannelData[channel], selfInt32ChannelData[channel], Int(self.frameLength) * MemoryLayout<Int32>.size)
            }
        }

        return copyBuffer
    }

    /// Appends samples from a source buffer into this one, expanding the length of the buffer until it reaches the capacity.
    /// - Parameter from: Buffer to append, beginning at index 0. Only the number of samples that will fit within the remaining capacity available are copied over.
    public func appendSamples(from src: AVAudioPCMBuffer) {
        // safeCopyWithResize() supports extending destination length (provided destination has capacity remaining)
        let dest = self
        safeCopyWithResize(destIdx: dest.frameLength, from: src, srcIdx: 0, frameCount: src.frameLength)
    }

    /// Safely copies samples into this buffer, expanding the buffer until it reaches capacity.
    /// - Parameter destIdx: Destination index within the buffer to copy into. This must be within the current occupied portion of the bufffer (that is, within its `frameLength`).
    /// - Parameter from: The source buffer to copy from.
    /// - Parameter srcIdx: The index in the source buffer to begin copying from.
    /// - Parameter frameCount: The number of frames to copy. If this overruns the source buffer length, only the valid number of frames will be copied. If it overruns the destination buffer length, the buffer will be expanded up to its capacity.
    public func safeCopyWithResize(destIdx: AVAudioFrameCount, from src: AVAudioPCMBuffer, srcIdx: AVAudioFrameCount, frameCount: AVAudioFrameCount) {
        let dest = self
        assert(dest.format == src.format)
        assert(dest.format.channelCount == 1)
        if let destSamples = dest.int16ChannelData, let srcSamples = src.int16ChannelData {
            Self.safeCopySamplesWithResize(dest: dest, destSamples: destSamples, destIdx: destIdx, src: src, srcSamples: srcSamples, srcIdx: srcIdx, frameCount: frameCount)
        } else if let destSamples = dest.int32ChannelData, let srcSamples = src.int32ChannelData {
            Self.safeCopySamplesWithResize(dest: dest, destSamples: destSamples, destIdx: destIdx, src: src, srcSamples: srcSamples, srcIdx: srcIdx, frameCount: frameCount)
        } else if let destSamples = dest.floatChannelData, let srcSamples = src.floatChannelData {
            Self.safeCopySamplesWithResize(dest: dest, destSamples: destSamples, destIdx: destIdx, src: src, srcSamples: srcSamples, srcIdx: srcIdx, frameCount: frameCount)
        } else {
            log("Unable to copy because no samples exist")
        }
    }

    // Buffer copy
    private static func safeCopySamplesWithResize<T>(
        dest: AVAudioPCMBuffer,
        destSamples: UnsafePointer<UnsafeMutablePointer<T>>,
        destIdx: AVAudioFrameCount,
        src: AVAudioPCMBuffer,
        srcSamples: UnsafePointer<UnsafeMutablePointer<T>>,
        srcIdx: AVAudioFrameCount,
        frameCount: AVAudioFrameCount
    ) {
        //print("copy: destLen=\(dest.frameLength) destCap=\(dest.frameCapacity) destIdx=\(destIdx) <- srcLen=\(src.frameLength) srcCap=\(src.frameCapacity) srcIdx=\(srcIdx) count=\(frameCount)")

        // How many sample to copy so as not to overrun either buffer
        if srcIdx >= src.frameLength {
            // We can only copy valid data
            return
        }
        if destIdx > dest.frameLength {
            // Note > not >= because we can append to dest buffer (as long as we stay within allocated capacity, checked below)
            return
        }
        let numSrcSamples = (srcIdx + frameCount) > src.frameLength ? (src.frameLength - srcIdx) : frameCount           // clamp number of src samples to read to buffer limit
        let growDestSamples = (destIdx + frameCount) > dest.frameLength
        let numDestSamples = (destIdx + frameCount) > dest.frameCapacity ? (dest.frameCapacity - destIdx) : frameCount  // clamp number of dest samples to write to buffer limit
        let numSamplesToCopy = min(numSrcSamples, numDestSamples)                                                       // must use the smaller of the two to stay within buffer limits
        let sizeOfSampleType = MemoryLayout<T>.stride   // https://stackoverflow.com/questions/24662864/swift-how-to-use-sizeof
        let numBytesToCopy = sizeOfSampleType * Int(numSamplesToCopy)
        if numBytesToCopy <= 0 {
            return
        }

        // Copy
        let destPtr = UnsafeMutableBufferPointer(start: destSamples.pointee, count: Int(dest.frameCapacity))
        let srcPtr = UnsafeBufferPointer(start: srcSamples.pointee, count: Int(src.frameCapacity))
        if let destBaseAddress = destPtr.baseAddress, let srcBaseAddress = srcPtr.baseAddress {
            let srcAddress = srcBaseAddress.advanced(by: Int(srcIdx))
            let destAddress = destBaseAddress.advanced(by: Int(destIdx))
            memcpy(destAddress, srcAddress, numBytesToCopy)

            // Adjust destination buffer size of we wrote past current length
            if growDestSamples {
                dest.frameLength = destIdx + numSamplesToCopy
            }
        }
    }

    public func convertToCMSampleBuffer(presentationTimeStamp: CMTime? = nil) -> CMSampleBuffer? {
        // https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
        let pcmBuffer = self
        guard pcmBuffer.frameLength > 0 else {
            // When audio buffer has 0 frames, this function fails. Return nil early.
            return nil
        }

        let audioBufferList = pcmBuffer.mutableAudioBufferList
        let asbd = pcmBuffer.format.streamDescription

        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        var status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        )

        if (status != noErr) {
            return nil
        }

        var timing: CMSampleTimingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: presentationTimeStamp ?? CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: CMTime.invalid
        )

        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(pcmBuffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        if (status != noErr) {
            log("CMSampleBufferCreate failed: \(status)")
            return nil
        }

        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        )

        if (status != noErr) {
            log("CMSampleBufferSetDataBufferFromAudioBufferList failed: \(status)")
            return nil
        }

        return sampleBuffer
    }
}

fileprivate func log(_ message: String) {
    print("[AVAudioPCMBuffer] \(message)")
}
