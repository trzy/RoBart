//
//  SpeechDetector.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//

import Combine
import AVFoundation

class SpeechDetector: ObservableObject {
    @Published private(set) var speech: String = ""

    private let _maxSpeechSeconds = 30
    private var _speechBuffer: AVAudioPCMBuffer!

    private var _isListening = false
    private var _subscription: Cancellable?

    private var _audioEngine = AVAudioEngine()
    private var _silenceInputMixerNode = AVAudioMixerNode()
    private var _playerNode = AVAudioPlayerNode()
    private var _converter: AVAudioConverter?
    private let _outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

    private let _voiceExtractor = VoiceExtractor()

    init() {
        // Create output buffer to hold detected speech
        _speechBuffer = createSpeechBuffer(format: _outputFormat)
        guard _speechBuffer != nil else {
            fatalError("Unable to allocate speech buffer")
        }

        // Start listening and subscribe to role changes
        if Settings.shared.role == .robot {
            startListening()
        }
        _subscription = Settings.shared.$role.sink { [weak self] (role: Role) in
            guard let self = self else { return }
            if role == .robot && !_isListening {
                startListening()
            } else if role != .robot && _isListening {
                stopListening()
            }
        }
    }

    private func startListening() {
        guard !_isListening else { return }
        log("Starting speech detector")
        _isListening = true
        setupAudioSession()
        setupAudioGraph()
        startAudioEngine()
    }

    private func stopListening() {
        guard _isListening else { return }
        log("Stopping speech detector")
        _isListening = false
        _silenceInputMixerNode.removeTap(onBus: 0)
        _audioEngine.stop()
        tearDownAudioGraph()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [ .defaultToSpeaker ])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            log("Error: AVAudioSession: \(error)")
        }
    }

    private func setupAudioGraph() {
        // Feed input into mixer node that suppresses audio to avoid feedback while recording. For
        // some reason, need to reduce input volume to 0 (which doesn't affect taps on this node,
        // evidently). Output volume has no effect unless changed *after* the node is attached to
        // the engine and then ends up silencing output as well.
        _silenceInputMixerNode.volume = 0
        _audioEngine.attach(_silenceInputMixerNode)

        // Input node -> silencing mixer node
        let inputNode = _audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        _audioEngine.connect(inputNode, to: _silenceInputMixerNode, format: inputFormat)

        // Connect to main mixer node. We can change the number of samples but not the sample rate
        // here.
        let mainMixerNode = _audioEngine.mainMixerNode
        let mixerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false)
        _audioEngine.connect(_silenceInputMixerNode, to: mainMixerNode, format: mixerFormat)

        // Create an output node for playback
        _audioEngine.attach(_playerNode)    // output player
        _audioEngine.connect(_playerNode, to: _audioEngine.mainMixerNode, format: mixerFormat)

        // Start audio engine
        _audioEngine.prepare()
    }

    private func tearDownAudioGraph() {
        _audioEngine.disconnectNodeInput(_silenceInputMixerNode)
        _audioEngine.disconnectNodeOutput(_silenceInputMixerNode)
        _audioEngine.disconnectNodeInput(_playerNode)
        _audioEngine.disconnectNodeOutput(_playerNode)
        _audioEngine.disconnectNodeInput(_audioEngine.inputNode)
        _audioEngine.disconnectNodeOutput(_audioEngine.inputNode)
        _audioEngine.disconnectNodeInput(_audioEngine.mainMixerNode)
        _audioEngine.disconnectNodeOutput(_audioEngine.mainMixerNode)
        _audioEngine.detach(_silenceInputMixerNode)
        _audioEngine.detach(_playerNode)
    }

    private func startAudioEngine() {
        // Create converter to convert audio to Deepgram and VAD format
        let format = _silenceInputMixerNode.outputFormat(forBus: 0)
        _converter = createConverter(from: format, to: _outputFormat)

        // Install a tap to acquire microphone audio
        _silenceInputMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            guard let self = self else { return }

            guard let audioBuffer = convertAudio(buffer) else { return }

            // Use VAD to minimize voice uploads
            let numSpeechFrames = _voiceExtractor.process(outputSpeechBuffer: _speechBuffer, inputAudioBuffer: audioBuffer)
            if numSpeechFrames > 0 {
                log("Detected \(Double(numSpeechFrames) / _speechBuffer.format.sampleRate) sec of speech")

                // Send to Deepgram for transcription
                transcribe(_speechBuffer)

                // Reset speech buffer
                _speechBuffer.frameLength = 0
            }
        }

        // Start recording
        do {
            try _audioEngine.start()
            log("Started audio engine")
        } catch {
            print("[AudioRecorder] Audio Engine error: \(error)")
        }
    }

    private func createSpeechBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if _speechBuffer == nil {
            let numFrames = AVAudioFrameCount(ceil(format.sampleRate * Double(_maxSpeechSeconds)))
            _speechBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: numFrames)
            if _speechBuffer == nil {
                log("Error: Unable to allocate speech buffer")
            } else {
                log("Successfully created speech buffer with format: \(_speechBuffer!.format)")
            }
        }
        return _speechBuffer
    }

    private func createConverter(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioConverter? {
        if _converter == nil {
            _converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            if _converter == nil {
                log("Error: Unable to create audio converter!")
            }
        }
        return _converter
    }

    private func convertAudio(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = _converter else { return nil }

        guard let outputAudioBuffer = AVAudioPCMBuffer(pcmFormat: _outputFormat, frameCapacity: buffer.frameLength) else {
            log("Error: Unable to allocate output buffer for conversion")
            return nil
        }

        var error: NSError?
        var allSamplesReceived = false
        converter.convert(to: outputAudioBuffer, error: &error, withInputFrom: { (inNumPackets: AVAudioPacketCount, outError: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
            if allSamplesReceived {
                outError.pointee = .noDataNow
                return nil
            }
            allSamplesReceived = true
            outError.pointee = .haveData
            return buffer
        })

        guard error == nil else {
            log("Error: Failed to convert audio: \(error!.localizedDescription)")
            return nil
        }

        return outputAudioBuffer
    }

    private func toData(_ buffer: AVAudioPCMBuffer) -> Data? {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }

    private func transcribe(_ buffer: AVAudioPCMBuffer) {
        assert(buffer.format.sampleRate == 16000)
        assert(buffer.format.channelCount == 1)
        assert(buffer.format.commonFormat == AVAudioCommonFormat.pcmFormatInt16)
        let start = Date.timeIntervalSinceReferenceDate
        guard let sampleData = toData(buffer) else { return }
        _ = Task {
            if let transcript = await uploadAudioToDeepgram(sampleData) {
                log("Transcript: \(transcript)")
                DispatchQueue.main.async { [weak self] in
                    self?.speech = transcript
                }
            }
            let elapsedMilliseconds = Int((Date.timeIntervalSinceReferenceDate - start) / 1e-3)
            log("Deepgram took: \(elapsedMilliseconds) ms")
        }
    }
}

fileprivate func log(_ message: String) {
    print("[SpeechDetector] \(message)")
}
