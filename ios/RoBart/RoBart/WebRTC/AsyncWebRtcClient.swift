//
//  AsyncWebRtcClient.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 12/27/25.
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

import Combine
import WebRTC

// Bundle offer SDP like this (on JavaScript side, this is the expected format)
fileprivate struct Offer: nonisolated Codable {
    var type = "offer"
    var sdp: String

    static func decode(jsonString: String) -> Offer? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        do {
            let offer = try decoder.decode(Offer.self, from: jsonData)
            return offer
        } catch {
            print("[WebRTCClient] Error decoding offer: \(error.localizedDescription)")
        }
        return nil
    }
}

// Bundle answer SDP like this
fileprivate struct Answer: nonisolated Codable {
    var type = "answer"
    var sdp: String

    static func decode(jsonString: String) -> Answer? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        do {
            let offer = try decoder.decode(Answer.self, from: jsonData)
            return offer
        } catch {
            print("[WebRTCClient] Error decoding answer: \(error.localizedDescription)")
        }
        return nil
    }
}

// Bundle ICE candidate like this
fileprivate struct ICECandidate: nonisolated Codable {
    let candidate: String
    let sdpMLineIndex: Int32
    let sdpMid: String?

    static func decode(jsonString: String) -> ICECandidate? {
        guard let jsonData = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        do {
            let offer = try decoder.decode(ICECandidate.self, from: jsonData)
            return offer
        } catch {
            print("[WebRTCClient] Error decoding ICE candidate: \(error.localizedDescription)")
        }
        return nil
    }
}

actor AsyncWebRtcClient: ObservableObject {
    // MARK: Internal errors

    fileprivate enum InternalError: Error {
        case failedToCreatePeerConnection
        case roleAssignmentFailed
        case sdpExchangeTimedOut
        case failedToCreateAnswerSdp
        case failedToCreateOfferSdp
        case failedToCreateLocalSdpString
        case peerConnectionTimedOut
        case peerDisconnected
    }

    // MARK: Internal state

    private let _factory: RTCPeerConnectionFactory

    // Continuations for API streams
    private var _isConnectedContinuation: AsyncStream<Bool>.Continuation?
    private var _peerConnectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation?
    private var _readyToConnectEventContinuation: AsyncStream<Void>.Continuation?
    private var _offerToSendContinuation: AsyncStream<String>.Continuation?
    private var _iceCandidateToSendContinuation: AsyncStream<String>.Continuation?
    private var _answerToSendContinuation: AsyncStream<String>.Continuation?
    private var _textDataReceivedContinuation: AsyncStream<String>.Continuation?

    /// Task used to run complete WebRTC flow
    private var _mainTask: Task<Bool, Never>?

    /// Connection object that is created per connection
    private var _peerConnection: RTCPeerConnection?

    private let _stunServers = [
        "stun:stun.l.google.com:19302",
        "stun:stun.l.google.com:5349",
        "stun:stun1.l.google.com:3478",
        "stun:stun1.l.google.com:5349",
        "stun:stun2.l.google.com:19302",
        "stun:stun2.l.google.com:5349",
        "stun:stun3.l.google.com:3478",
        "stun:stun3.l.google.com:5349",
        "stun:stun4.l.google.com:19302",
        "stun:stun4.l.google.com:5349"
    ]

    private let _mediaConstraints = RTCMediaConstraints(
        mandatoryConstraints: [
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        ],
        optionalConstraints: nil
    )

    nonisolated private let _audioSession = RTCAudioSession.sharedInstance()
    nonisolated private let _audioQueue = DispatchQueue(label: "audioSessionConfiguration")

    private var _desiredCamera = CameraType.backDefault
    private var _isCapturing = false

    private var _dataChannel: RTCDataChannel?
    private var _videoCapturer: RTCVideoCapturer?
    private var _localVideoTrack: RTCVideoTrack?
    private var _remoteVideoTrack: RTCVideoTrack?

    private var _iceCandidateQueue: [RTCIceCandidate] = []

    private var _sdpReceivedContinuation: AsyncStream<RTCSessionDescription>.Continuation?
    private var _serverConfigContinuation: AsyncStream<ServerConfiguration>.Continuation?
    private var _iceCandidateReceivedContinuation: AsyncStream<RTCIceCandidate>.Continuation?


    // MARK: Delegate objects (because actor cannot directly conform to RTC delegate protocols)

    fileprivate class RtcDelegateAdapeter: NSObject {
        var client: AsyncWebRtcClient?
    }

    private let _rtcDelegateAdapter: RtcDelegateAdapeter

    // MARK: API - Server Configuration

    enum Role {
        case initiator
        case responder
    }

    struct ServerConfiguration {
        let role: Role
        let turnServers: [String]
        let turnUsers: [String?]
        let turnPasswords: [String?]
    }

    // MARK: API - Session state (for e.g. UI)

    let isConnected: AsyncStream<Bool>

    // MARK: API - Generated messages to transmit to peers via external signal transport

    let readyToConnectEvent: AsyncStream<Void>
    let offerToSend: AsyncStream<String>
    let iceCandidateToSend: AsyncStream<String>
    let answerToSend: AsyncStream<String>

    // MARK: API - Data received via WebRTC

    let textDataReceived: AsyncStream<String>

    // MARK: API - Methods

    init(queue: DispatchQueue = .main) {
        //RTCSetMinDebugLogLevel(RTCLoggingSeverity.info)

        _factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )

        // Create streams
        var boolContinuation: AsyncStream<Bool>.Continuation?
        var voidContinuation: AsyncStream<Void>.Continuation?
        var stringContinuation: AsyncStream<String>.Continuation?

        isConnected = AsyncStream { continuation in
            boolContinuation = continuation
        }
        _isConnectedContinuation = boolContinuation

        readyToConnectEvent = AsyncStream { continuation in
            voidContinuation = continuation
        }
        _readyToConnectEventContinuation = voidContinuation

        offerToSend = AsyncStream { continuation in
            stringContinuation = continuation
        }
        _offerToSendContinuation = stringContinuation

        iceCandidateToSend = AsyncStream { continuation in
            stringContinuation = continuation
        }
        _iceCandidateToSendContinuation = stringContinuation

        answerToSend = AsyncStream { continuation in
            stringContinuation = continuation
        }
        _answerToSendContinuation = stringContinuation

        textDataReceived = AsyncStream { continuation in
            stringContinuation = continuation
        }
        _textDataReceivedContinuation = stringContinuation

        // Delegate adapters -- this is all bullshit machinery to work around actor restrictions
        _rtcDelegateAdapter = RtcDelegateAdapeter()
        _rtcDelegateAdapter.client = self
    }

    func run() async {
        while true {
            let task = Task { return await self.runOneSession() }
            _mainTask = task
            let wasCanceled = await task.value
            if wasCanceled {
                // If explicitly canceled, finish; otherwise, keep trying
                log("WebRTC run canceled!")
                return
            } else {
                log("Retrying...")
            }
        }
    }

    func switchToCamera(_ cameraType: CameraType) async {
        _desiredCamera = cameraType

        if _isCapturing {
            log("Switching cameras...")
            stopCapture()
            startCapture()
        }
    }

    func addRemoteVideoView(_ renderer: RTCVideoRenderer) async {
        _remoteVideoTrack?.add(renderer)
    }

    func removeRemoteVideoView(_ renderer: RTCVideoRenderer) async {
        _remoteVideoTrack?.remove(renderer)
    }

    /// Cancel current connection or connection attempt and try to reconnect. Required when
    /// signaling layer disconnects.
    func reconnect() async {
        log("Stopping...")
        _mainTask?.cancel()
    }

    /// Sets role and TURN server information, which will govern which side will kick off the
    /// connection process by producing an offer once the other side is present. This is assigned
    /// by our signaling server.
    func onServerConfigurationReceived(_ config: ServerConfiguration) async {
        _serverConfigContinuation?.yield(config)
    }

    /// Accept offer from a remote peer.
    func onOfferReceived(jsonString: String) async {
        log("Received offer")
        guard let offer = Offer.decode(jsonString: jsonString) else { return }
        let sdp = RTCSessionDescription(type: .offer, sdp: offer.sdp)
        _sdpReceivedContinuation?.yield(sdp)
    }

    /// Accept answer from a remote peer.
    func onAnswerReceived(jsonString: String) async {
        log("Received answer")
        guard let answer = Answer.decode(jsonString: jsonString) else { return }
        let sdp = RTCSessionDescription(type: .answer, sdp: answer.sdp)
        _sdpReceivedContinuation?.yield(sdp)
    }

    /// Accept an ICE candidate from the remote peer.
    func onIceCandidateReceived(jsonString: String) async {
        guard let iceCandidate = ICECandidate.decode(jsonString: jsonString) else { return }
        let candidate = RTCIceCandidate(
            sdp: iceCandidate.candidate,
            sdpMLineIndex: iceCandidate.sdpMLineIndex,
            sdpMid: iceCandidate.sdpMid
        )

        if let continuation = _iceCandidateReceivedContinuation {
            // If SDP exchange is complete, a stream will have been set up to process these as they
            // arrive
            log("Received ICE candidate message from remote peer")
            continuation.yield(candidate)
        } else {
            // Otherwise, enqueue them
            log("Received and enqueued ICE candidate message from remote peer")
            _iceCandidateQueue.append(candidate)
        }
    }

    /// Send a string on the chat data channel.
    func sendTextData(_ text: String) async {
        let buffer = RTCDataBuffer(data: text.data(using: .utf8)!, isBinary: false)
        guard let dataChannel = _dataChannel else {
            logError("No data channel to send on")
            return
        }
        dataChannel.sendData(buffer)
    }

    // MARK: Internal

    /// Runs the client for one connection session and returns true if canceled, otherwise false
    /// if either an error or a disconnect occurred.
    private func runOneSession() async -> Bool {
        log("Running session...")

        defer {
            stopCapture()
            closeConnection()
        }

        do {
            try Task.checkCancellation()

            // Create connection state monitoring stream. We need to do this each time because
            // when the loop that awaits this later on is interrupted, the stream will close.
            var peerConnectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation?
            let peerConnectionState = AsyncStream { continuation in
                peerConnectionStateContinuation = continuation
            }
            _peerConnectionStateContinuation = peerConnectionStateContinuation

            // Notify signal server we are ready to begin connection process. Once the
            // other peer signals the same, roles will be distributed and we may proceed.
            guard let config = try await startConnectionProcessAndWaitForServerConfig() else {
                throw InternalError.roleAssignmentFailed
            }

            // Clear out ICE candidate queue. This may be populated even before SDP exchange,
            // and we must buffer them until after that completes.
            _iceCandidateQueue = []
            try await createConnection(config)

            // Kick off connection process and wait for exchange of SDPs (offer and answer) to
            // occur before proceeding
            try await withThrowingTaskGroup(of: Void.self) { group in
                var gotSDP = false

                // Wait for SDP (offer or answer) and respond with answer if we are responder.
                // Task group is useful here because this task need not be explicitly canceled
                // if there is a subsequent failure in the group.
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    try await waitForSdp()
                    if config.role == .responder {
                        try await createAndSendAnswer()
                    }
                    gotSDP = true
                }

                // If we are the initiator, create and send an offer
                if config.role == .initiator {
                    try await createAndSendOffer()
                }

                // Wait up to N seconds for SDP exchange. If the other task does not succeed
                // in the meantime, this will throw, and the entire group will be canceled.
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    let numSecondsToWait = 10
                    let intervals = Int(Float(numSecondsToWait) / 0.1) + 1
                    for _ in 1...intervals {
                        if await _peerConnection?.remoteDescription != nil {  // could also check "gotSDP"
                            return
                        }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    throw InternalError.sdpExchangeTimedOut
                }

                // Wait for one of the exchange tasks to complete (this also rethrows)
                for try await _ in group {
                    // Something should have succeeded. If timeout task failed, we should not
                    // be here (unless outer task canceled)...
                    try Task.checkCancellation()
                    precondition(gotSDP == true)
                    return
                }
            }

            try Task.checkCancellation()
            log("SDP exchanged")

            // We should be connected and can accept remote ICE candidates now and wait until
            // the connection finishes
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Wait up to N seconds for RTC session to be established
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    try await Task.sleep(for: .seconds(10))
                    if await _peerConnection?.connectionState != .connected {
                        throw InternalError.peerConnectionTimedOut
                    }
                }

                // Once connected, any subsequent disconnect should terminate this connection
                group.addTask { [weak self] in
                    guard let self = self else { return }

                    // Wait for connect. We must be careful to iterate _peerConnectionState only
                    // once. It is not possible to break and resume.
                    var isConnected = false
                    for await state in peerConnectionState {
                        if !isConnected {
                            if state == .connected {
                                log("Reached connected state")
                                isConnected = true

                                // Start media capture once connected
                                await startCapture()
                                log("Monitoring for connection failure...")
                            } else if state == .failed {
                                log("Connection never formed")
                                throw InternalError.peerDisconnected
                            }
                        } else {
                            // Already connected. Monitor for failure
                            if state == .failed {
                                logError("Disconnected!")
                                throw InternalError.peerDisconnected
                            }
                        }
                    }
                }

                // Process ICE candidates as they come
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    try await processIceCandidates()
                }

                // Wait for all and rethrow (waitForAll() does not seem to do so?)
                for try await _ in group {
                }
            }
        } catch is CancellationError {
            log("WebRTC task was canceled")
            return true // was canceled
        } catch {
            logError(error.localizedDescription)
        }

        return false
    }

    private func createConnection(_ serverConfig: ServerConfiguration) async throws {
        log("Creating peer connection")

        let (config, constraints) = createConnectionConfiguration(serverConfig: serverConfig)
        guard let peerConnection = _factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            throw InternalError.failedToCreatePeerConnection
        }

        // Wire up peer connection delegate and store peer connection
        let task = Task { @MainActor in
            // WebRTC API is apparently main actor isolated
            peerConnection.delegate = _rtcDelegateAdapter
        }
        await task.value
        _peerConnection = peerConnection

        // Create a data channel
        if let dataChannel = peerConnection.dataChannel(forLabel: "chat", configuration: RTCDataChannelConfiguration()) {
            let task = Task { @MainActor in
                dataChannel.delegate = _rtcDelegateAdapter
            }
            await task.value
            _dataChannel = dataChannel
            log("Created data channel")
        }

        // Create audio track
        let audioTrack = createAudioTrack()
        peerConnection.add(audioTrack, streamIds: [ "stream" ])

        // Create video track
        let (videoCapturer, videoTrack) = createVideoCapturerAndTrack()
        _videoCapturer = videoCapturer
        _localVideoTrack = videoTrack
        peerConnection.add(videoTrack, streamIds: [ "stream" ])
        _remoteVideoTrack = peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
    }

    private func waitForSdp() async throws {
        log("Waiting for remote SDP")

        let sdpStream: AsyncStream<RTCSessionDescription> = AsyncStream { continuation in
            _sdpReceivedContinuation = continuation
        }

        for await sdp in sdpStream {
            try await _peerConnection?.setRemoteDescription(sdp)
            log("Received remote SDP")
            break
        }

        _sdpReceivedContinuation = nil
        try Task.checkCancellation()
    }

    private func createAndSendAnswer() async throws {
        guard let sdp = try await _peerConnection?.answer(for: _mediaConstraints) else {
            throw InternalError.failedToCreateAnswerSdp
        }
        try await _peerConnection?.setLocalDescription(sdp)
        guard let sdpString = _peerConnection?.localDescription?.sdp else {
            throw InternalError.failedToCreateLocalSdpString
        }
        let container = String(data: try! JSONEncoder().encode(Answer(sdp: sdpString)), encoding: .utf8)!
        _answerToSendContinuation?.yield(container)
        log("Sent answer")
    }

    private func createAndSendOffer() async throws {
        guard let sdp = try await _peerConnection?.offer(for: _mediaConstraints) else {
            throw InternalError.failedToCreateOfferSdp
        }
        try await _peerConnection?.setLocalDescription(sdp)
        guard let sdpString = _peerConnection?.localDescription?.sdp else {
            throw InternalError.failedToCreateLocalSdpString
        }
        let container = String(data: try! JSONEncoder().encode(Offer(sdp: sdpString)), encoding: .utf8)!
        _offerToSendContinuation?.yield(container)
        log("Sent offer")
    }

    private func startConnectionProcessAndWaitForServerConfig() async throws -> ServerConfiguration? {
        let configStream: AsyncStream<ServerConfiguration> = AsyncStream { continuation in
            _serverConfigContinuation = continuation
        }

        // Indicate to signaling server that we are ready to begin connecting. Server will respond
        // with role.
        _readyToConnectEventContinuation?.yield()
        log("Ready to start connection process")

        // Await role. This waits indefinitely unless the entire task is canceled by a disconnect
        for await config in configStream {
            _serverConfigContinuation = nil
            let servers = config.turnServers.count == 0 ? "none" : (config.turnServers.joined(separator: ", "))
            log("Received server configuration: role=\(config.role == .initiator ? "initiator" : "responder"), TURN server=\(servers)")
            return config
        }

        _serverConfigContinuation = nil
        try Task.checkCancellation()
        return nil
    }

    private func processIceCandidates() async throws {
        let iceCandidateStream: AsyncStream<RTCIceCandidate> = AsyncStream { continuation in
            _iceCandidateReceivedContinuation = continuation
        }

        // First process any enqueued candidates
        let iceCandidateQueue = _iceCandidateQueue
        _iceCandidateQueue = []
        for candidate in iceCandidateQueue {
            log("Adding ICE candidate...")
            try await _peerConnection?.add(candidate)
        }
        log("Processed \(iceCandidateQueue.count) enqueued ICE candidates")

        // Process any ICE candidates coming in from this point onwards using stream
        for await candidate in iceCandidateStream {
            try await _peerConnection?.add(candidate)
            try Task.checkCancellation()
            log("Processed ICE candidate")
        }

        _iceCandidateReceivedContinuation = nil
        try Task.checkCancellation()
    }

    private func createConnectionConfiguration(serverConfig: ServerConfiguration) -> (RTCConfiguration, RTCMediaConstraints) {
        let config = RTCConfiguration()
        config.bundlePolicy = .maxCompat                        // ?
        config.continualGatheringPolicy = .gatherContinually    // ?
        config.rtcpMuxPolicy = .require                         // ?
        config.iceTransportPolicy = .all
        config.tcpCandidatePolicy = .enabled
        config.keyType = .ECDSA

        // STUN servers
        var iceServers = [
            RTCIceServer(urlStrings: _stunServers)
        ]

        // TURN servers, if we have any
        if serverConfig.turnServers.count != serverConfig.turnUsers.count || serverConfig.turnUsers.count != serverConfig.turnPasswords.count {
            logError("Ignoring TURN servers because server \(serverConfig.turnServers.count), username \(serverConfig.turnUsers.count), and password (\(serverConfig.turnPasswords.count)) counts do not match")
        } else {
            for i in 0..<serverConfig.turnServers.count {
                let turnServer = RTCIceServer(
                    urlStrings: [ "turn:\(serverConfig.turnServers[i])" ],
                    username: serverConfig.turnUsers[i],
                    credential: serverConfig.turnPasswords[i]
                )
                iceServers.append(turnServer)
            }
        }

        config.iceServers = iceServers

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                // Allegedly required for sharing streams with browswers
                "DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )

        return (config, constraints)
    }

    private func closeConnection() {
        _peerConnection?.close()
        _peerConnection = nil
        _dataChannel = nil
        _videoCapturer = nil
        _localVideoTrack = nil
        _remoteVideoTrack = nil
    }

    /// Use speaker output. This must be done after each new connection and audio track are created
    /// and cannot be done once at initialization (unless, I suppose, those objects are reused?).
    /// It seems only to work after video capture has started.
    private func switchAudioToSpeakerphone() {
        _audioQueue.async { [weak self] in
            guard let self = self else { return }
            _audioSession.lockForConfiguration()
            do {
                try _audioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try _audioSession.setMode(AVAudioSession.Mode.voiceChat)
                try _audioSession.overrideOutputAudioPort(.speaker)
            } catch let error {
                logError("Unable to configure RTC audio session: \(error)")
            }
            _audioSession.unlockForConfiguration()
        }
    }

    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = _factory.audioSource(with: audioConstrains)
        let audioTrack = _factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }

    private func createVideoCapturerAndTrack() -> (RTCVideoCapturer, RTCVideoTrack) {
        let videoSource = _factory.videoSource()
        let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        let videoTrack = _factory.videoTrack(with: videoSource, trackId: "video0")
        return (videoCapturer, videoTrack)
    }

    private func startCapture() {
        guard let capturer = _videoCapturer as? RTCCameraVideoCapturer else { return }
        guard let camera = findCamera() else { return }
        guard let format = (RTCCameraVideoCapturer.supportedFormats(for: camera).sorted { (fmt1, fmt2) -> Bool in
            let width1 = CMVideoFormatDescriptionGetDimensions(fmt1.formatDescription).width
            let width2 = CMVideoFormatDescriptionGetDimensions(fmt2.formatDescription).width
            return width1 < width2
        }).last,
        let fps = (format.videoSupportedFrameRateRanges.sorted { $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }

        capturer.startCapture(with: camera, format: format, fps: Int(fps.maxFrameRate))
        switchAudioToSpeakerphone() // must configure audio here
        _isCapturing = true

        Task { @MainActor in
            print("Started video capture: \(format.formatDescription)")
        }
    }

    private func stopCapture() {
        guard _isCapturing else { return }
        guard let capturer = self._videoCapturer as? RTCCameraVideoCapturer else { return }
        capturer.stopCapture()
        _isCapturing = false
    }

    private func findCamera() -> AVCaptureDevice? {
        switch _desiredCamera {
        case .front:
            return RTCCameraVideoCapturer.captureDevices().first { $0.position == .front }
        case .backDefault:
            return RTCCameraVideoCapturer.captureDevices().first { $0.position == .back }
        case .backWide:
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            return session.devices.first ?? (RTCCameraVideoCapturer.captureDevices().first { $0.position == .back })
        case .backUltraWide:
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera],
                mediaType: .video,
                position: .back
            )
            return session.devices.first ?? (RTCCameraVideoCapturer.captureDevices().first { $0.position == .back })
        case .backTelephoto:
            let session = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTelephotoCamera],
                mediaType: .video,
                position: .back
            )
            return session.devices.first ?? (RTCCameraVideoCapturer.captureDevices().first { $0.position == .back })
        }
    }
}

extension AsyncWebRtcClient.RtcDelegateAdapeter: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateToString: [RTCIceConnectionState: String] = [
            .checking: "checking",
            .connected: "connected",
            .disconnected: "disconnected",
            .closed: "closed",
            .completed: "completed",
            .count: "count",
            .failed: "failed",
            .new: "new",
        ]
        let stateName = stateToString[newState] ?? "unknown (\(newState.rawValue))"
        log("ICE connection state: \(stateName)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let iceCandidate = ICECandidate(candidate: candidate.sdp, sdpMLineIndex: candidate.sdpMLineIndex, sdpMid: candidate.sdpMid)
        let serialized = String(data: try! JSONEncoder().encode(iceCandidate), encoding: .utf8)!
        log("Generated ICE candidate")
        Task { await client?._iceCandidateToSendContinuation?.yield(serialized) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        log("Data channel opened: \(dataChannel.description)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        let stateToString: [RTCPeerConnectionState: String] = [
            .closed: "closed",
            .connected: "connected",
            .connecting: "connecting",
            .disconnected: "disconnected",
            .failed: "failed",
            .new: "new"
        ]
        let stateName = stateToString[newState] ?? "unknown (\(newState.rawValue))"
        log("Peer connection state: \(stateName)")

        Task {
            await client?._peerConnectionStateContinuation?.yield(newState)
            await client?._isConnectedContinuation?.yield(newState == .connected)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
}

extension AsyncWebRtcClient.RtcDelegateAdapeter: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let stateToString: [RTCDataChannelState: String] = [
            .closed: "closed",
            .closing: "closing",
            .connecting: "connecting",
            .open: "open"
        ]
        let state = dataChannel.readyState
        let stateName = stateToString[state] ?? "unknown (\(state.rawValue))"
        log("Data channel state: \(stateName)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let textData = String(data: Data(buffer.data), encoding: .utf8) else { return }
        Task { await client?._textDataReceivedContinuation?.yield(textData) }
    }
}

extension AsyncWebRtcClient.InternalError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToCreatePeerConnection:
            return "Failed to create peer connection object"
        case .roleAssignmentFailed:
            return "Role assignment from signaling server failed"
        case .sdpExchangeTimedOut:
            return "SDP exchange process timed out"
        case .failedToCreateAnswerSdp:
            return "Failed to create answer SDP"
        case .failedToCreateOfferSdp:
            return "Failed to create offer SDP"
        case .failedToCreateLocalSdpString:
            return "Failed to obtain local SDP and serialize it to a string"
        case .peerConnectionTimedOut:
            return "Connection to peer timed out and could not be established"
        case .peerDisconnected:
            return "Peer disconnected"
        }
    }
}

fileprivate func log(_ message: String) {
    print("[AsyncWebRtcClient] \(message)")
}

fileprivate func logError(_ message: String) {
    print("[AsyncWebRtcClient] Error: \(message)")
}
