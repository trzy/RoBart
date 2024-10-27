//
//  AudioRecorder.swift
//  RoBart Remote Control Watch App
//
//  Created by Bart Trzynadlowski on 10/26/24.
//

import AVFoundation

class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var _audioEngine = AVAudioEngine()
    private let _outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
    private var _converter: AVAudioConverter?
    private var _chunkNumber = 0

    func startRecording(_ onAudioRecorded: @escaping (_ chunkNumber: Int, _ samples: Data) -> Void) {
        guard !isRecording else { return }

        _chunkNumber = 0

        do {
            try AVAudioSession.sharedInstance().setCategory(.record)
            try AVAudioSession.sharedInstance().setActive(true)

            // Get input node before calling prepare
            let inputNode = _audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            _audioEngine.prepare()

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                // Convert audio to output format
                guard let self = self else { return }
                guard let converter = getConverter(from: buffer.format) else { return }
                let outputFrameCapacity = AVAudioFrameCount(ceil(converter.outputFormat.sampleRate / buffer.format.sampleRate) * Double(buffer.frameLength))
                guard let outputAudioBuffer = AVAudioPCMBuffer(pcmFormat: _outputFormat, frameCapacity: outputFrameCapacity) else {
                    log("Error: Unable to allocate output buffer")
                    return
                }
                convertAudio(inputBuffer: buffer, outputBuffer: outputAudioBuffer, using: converter)

                // Append to recording buffer as raw PCM bytes
                guard let samples = outputAudioBuffer.int16ChannelData else { return }
                let ptr = UnsafeMutableBufferPointer(start: samples.pointee, count: Int(outputAudioBuffer.frameLength))
                ptr.withMemoryRebound(to: UInt8.self) { [weak self] (bytes: UnsafeMutableBufferPointer<UInt8>) -> Void in
                    guard let self = self else { return }
                    let data = Data(bytes: bytes.baseAddress!, count: bytes.count)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        onAudioRecorded(_chunkNumber, data)
                        _chunkNumber += 1
                    }
                    log("Recorded \(data.count) bytes")
                }
            }

            try _audioEngine.start()

            isRecording = true
        } catch {
            log("Recording failed: \(error)")
        }
    }

    func stopRecording() -> Int {
        guard isRecording else { return _chunkNumber }
        _audioEngine.stop()
        _audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        return _chunkNumber
    }

    private func getConverter(from inputFormat: AVAudioFormat) -> AVAudioConverter? {
        if _converter == nil {
            _converter = AVAudioConverter(from: inputFormat, to: _outputFormat)
            if _converter == nil {
                log("Error: Unable to create audio converter!")
            }
        }
        return _converter
    }

    private func convertAudio(inputBuffer: AVAudioPCMBuffer, outputBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        var error: NSError?
        var allSamplesReceived = false
        converter.convert(to: outputBuffer, error: &error, withInputFrom: { (inNumPackets: AVAudioPacketCount, outError: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            if allSamplesReceived {
                outError.pointee = .noDataNow
                return nil
            }
            allSamplesReceived = true
            outError.pointee = .haveData
            return inputBuffer
        })

        if let error = error {
            log("Error: Unable to convert audio: \(error.localizedDescription)")
        }
    }
}

fileprivate func log(_ message: String) {
    print("[AudioRecorder] \(message)")
}
