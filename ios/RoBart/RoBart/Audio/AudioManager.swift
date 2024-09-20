//
//  AudioManager.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/19/24.
//

import AVFoundation

class AudioManager {
    static let shared = AudioManager()

    private var _isRunning = false
    private var _audioEngine = AVAudioEngine()
    private var _silenceInputMixerNode = AVAudioMixerNode()
    private var _playerNode = AVAudioPlayerNode()
    private let _tempDir: URL

    fileprivate init() {
        _tempDir = FileManager.default.temporaryDirectory
    }

    func startRecording(onSamplesRecorded: @escaping AVAudioNodeTapBlock) {
        if !_isRunning {
            start()
        }
        let format = _silenceInputMixerNode.outputFormat(forBus: 0)
        _silenceInputMixerNode.installTap(onBus: 0, bufferSize: 4096, format: format, block: onSamplesRecorded)
    }

    func stopRecording() {
        _silenceInputMixerNode.removeTap(onBus: 0)
    }

    func playSound(url: URL, delete: Bool = false, continuation: AsyncStream<Void>.Continuation? = nil) {
        if !_isRunning {
            start()
        }

        guard let file = try? AVAudioFile(forReading: url) else {
            continuation?.finish()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?._playerNode.play()
            self?._playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in
                DispatchQueue.main.async { [weak self] in
                    // Prevents some sort of crash/deadlock: https://stackoverflow.com/questions/59080708/calling-stop-on-avaudioplayernode-after-finished-playing-causes-crash
                    log("Finished playback")
                    self?._playerNode.stop()
                    if delete {
                        try? FileManager.default.removeItem(at: url)
                    }
                    continuation?.finish()
                }
            }
            log("Started playback")
        }
    }

    func playSound(fileData: Data) async {
        let tempFile = _tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp3")
        do {
            try fileData.write(to: tempFile)
            let stream = AsyncStream<Void> { [weak self] continuation in
                guard let self = self else {
                    continuation.finish()
                    return
                }
                playSound(url: tempFile, delete: true, continuation: continuation)
            }
            var it = stream.makeAsyncIterator()
            _ = await it.next()
        } catch {
            log("Error: Unable to write to temporary file: \(error.localizedDescription)")
        }
    }

    private func start() {
        guard !_isRunning else { return }
        setupAudioSession()
        setupAudioGraph()
        startAudioEngine()
        _isRunning = true
    }

    private func stop() {
        guard _isRunning else { return }
        log("Stopping audio manager")
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
        do {
            try _audioEngine.start()
            log("Started audio engine")
        } catch {
            print("[AudioRecorder] Could not start audio engine: \(error)")
        }
    }
}

fileprivate func log(_ message: String) {
    print("[AudioManager] \(message)")
}
