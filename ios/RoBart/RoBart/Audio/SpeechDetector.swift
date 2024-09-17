//
//  SpeechDetector.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//

import AVFoundation

class SpeechDetector {
    private let _maxSpeechSeconds = 5
    private var _speechBuffer: AVAudioPCMBuffer?

    private var _audioEngine = AVAudioEngine()
    private var _silenceInputMixerNode = AVAudioMixerNode()
    private var _playerNode = AVAudioPlayerNode()

    private let _voiceExtractor = VoiceExtractor()

    init() {
    }

    func startListening() {
        setupAudioSession()
        setupAudioGraph()
        startAudioEngine()
    }

    func stopListening() {
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

    var isPlaying = false

    private func startAudioEngine() {
        // Create output buffer to hold detected speech
        let format = _silenceInputMixerNode.outputFormat(forBus: 0)
        _speechBuffer = createSpeechBuffer(captureFormat: format)
        guard let speechBuffer = _speechBuffer else {
            log("Error: Unable to allocate speech buffer")
            return
        }

        // Install a tap to acquire microphone audio
        _silenceInputMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            guard let self = self else { return }

            if isPlaying {
                return
            }

            let numSpeechFrames = _voiceExtractor.process(outputSpeechBuffer: speechBuffer, inputAudioBuffer: buffer)
            if numSpeechFrames > 0 {
                log("DETECTED \(Double(numSpeechFrames) / format.sampleRate) sec of speech!")

                isPlaying = true
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    _playerNode.prepare(withFrameCount: speechBuffer.frameLength)
                    _playerNode.play()
                    isPlaying = true
                    _playerNode.scheduleBuffer(speechBuffer, completionCallbackType: .dataPlayedBack) {_ in
                        DispatchQueue.main.async {
                            self._playerNode.stop()
                            self.isPlaying = false
                            log("Stopped")

                            // Reset speech buffer
                            speechBuffer.frameLength = 0
                        }
                    }
                }
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

    private func createSpeechBuffer(captureFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if _speechBuffer == nil {
            let numFrames = AVAudioFrameCount(ceil(captureFormat.sampleRate * Double(_maxSpeechSeconds)))
            _speechBuffer = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: numFrames)
            if _speechBuffer == nil {
                log("Error: Unable to allocate audio capture buffer")
            } else {
                log("Successfully created audio capture buffer with format: \(_speechBuffer!.format)")
            }
        }
        return _speechBuffer
    }


}

fileprivate func log(_ message: String) {
    print("[SpeechDetector] \(message)")
}
