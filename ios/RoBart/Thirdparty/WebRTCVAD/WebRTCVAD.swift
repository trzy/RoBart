//
//  WebRTCVAD.swift
//  WebRTCVAD
//
//  Created by Bart Trzynadlowski on 4/19/23.
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

public class WebRTCVAD {
    public enum Aggressiveness: Int32 {
        case LeastAggressive = 0    // this happens to be the default internally
        case LessAggressive = 1
        case MoreAggressive = 2
        case MostAggressive = 3
    }

    private let _handle: OpaquePointer
    private let _inputAudioBuffer: AVAudioPCMBuffer
    private let _inputChunkFrames: AVAudioFrameCount
    private let _vadAudioBuffer: AVAudioPCMBuffer
    private let _vadChunkFrames: AVAudioFrameCount
    private let _audioConverter: AVAudioConverter
    private let _vadFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

    public var inputChunkFrames: AVAudioFrameCount {
        return _inputChunkFrames
    }

    public init(aggressiveness: Aggressiveness = Aggressiveness.LeastAggressive, inputAudioFormat: AVAudioFormat, chunkSeconds: Double = 30e-3) {
        // Create a buffer to hold a chunk of audio in the input format
        _inputChunkFrames = AVAudioFrameCount(ceil(inputAudioFormat.sampleRate * chunkSeconds))
        guard let inputAudioBuffer = AVAudioPCMBuffer(pcmFormat: inputAudioFormat, frameCapacity: _inputChunkFrames) else {
            fatalError("[WebRTCVAD] Unable to create audio buffer")
        }
        _inputAudioBuffer = inputAudioBuffer

        // Create a buffer to hold a chunk of audio in the VAD input format
        _vadChunkFrames = AVAudioFrameCount(ceil(_vadFormat.sampleRate * chunkSeconds))
        guard let vadAudioBuffer = AVAudioPCMBuffer(pcmFormat: _vadFormat, frameCapacity: _vadChunkFrames) else {
            fatalError("[WebRTCVAD] Unable to create audio buffer")
        }
        _vadAudioBuffer = vadAudioBuffer

        // Create audio converter from input -> VAD format
        guard let audioConverter = AVAudioConverter(from: inputAudioFormat, to: _vadFormat) else {
            fatalError("[WebRTCVAD] Unable to create audio converter")
        }
        _audioConverter = audioConverter

        // Create WebRTC VAD object
        _handle = WebRtcVad_Create()
        if WebRtcVad_Init(_handle) != 0 {
            fatalError("[WebRTCVAD] Failed to initialize Voice Activity Detector")
        }
        WebRtcVad_set_mode(_handle, aggressiveness.rawValue)
    }

    deinit {
        WebRtcVad_Free(_handle)
    }

    public func isVoice(buffer: AVAudioPCMBuffer, from startIdx: AVAudioFrameCount) -> Bool {
        assert(buffer.format.channelCount == 1)

        // Copy from buffer to our input buffer
        _inputAudioBuffer.frameLength = 0
        _inputAudioBuffer.safeCopyWithResize(destIdx: 0, from: buffer, srcIdx: startIdx, frameCount: _inputChunkFrames)

        // Convert only if necessary
        var vadAudioBuffer: AVAudioPCMBuffer?
        if _inputAudioBuffer.format == _vadFormat {
            vadAudioBuffer = _inputAudioBuffer
        } else {
            guard tryConvertAudioToVADFormat() else {
                return false
            }
            vadAudioBuffer = _vadAudioBuffer
        }

        // Run VAD
        guard let samples = vadAudioBuffer!.int16ChannelData else {
            return false
        }
        return WebRtcVad_Process(_handle, Int32(_vadFormat.sampleRate), samples.pointee, Int(vadAudioBuffer!.frameLength)) == 1
    }

    private func tryConvertAudioToVADFormat() -> Bool {
        // Perform conversion to model input format. No need to reset frameLength to 0 because this
        // function appears to always fill from the start of the buffer.
        var error: NSError?
        var allSamplesReceived = false
        _audioConverter.convert(to: _vadAudioBuffer, error: &error, withInputFrom: { (inNumPackets: AVAudioPacketCount, outError: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            // This is the input block that is called repeatedly over and over until the destination is filled
            // to capacity. But that isn't the behavior we want! We want to stop after we have converted the
            // complete input and do not want it to repeat. Hence, we have to do some ridiculous trickery to
            // stop it because whoever designed this API is a maniac. For more details see:
            // https://www.appsloveworld.com/swift/100/27/avaudioconverter-with-avaudioconverterinputblock-stutters-audio-after-processing
            if allSamplesReceived {
                outError.pointee = .noDataNow
                return nil
            }
            allSamplesReceived = true
            outError.pointee = .haveData
            return self._inputAudioBuffer
        })
        if let error = error {
            print("[WebRTCVAD] Error: Unable to convert audio: \(error.localizedDescription)")
            return false
        }

        // Success
        return true
    }
}
