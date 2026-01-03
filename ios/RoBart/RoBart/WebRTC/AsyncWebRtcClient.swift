//
//  AsyncWebRtcClient.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 1/1/26.
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
import WebRTC

/// WebRTC client that continuously attempts to connect and maintain a session.
actor AsyncWebRtcClient: ObservableObject {
    //MARK: Internal members

    private let _factory = RTCPeerConnectionFactory(
        encoderFactory: RTCDefaultVideoEncoderFactory(),
        decoderFactory: RTCDefaultVideoDecoderFactory()
    )

    private let _mediaConstraints = RTCMediaConstraints(
        mandatoryConstraints: [
            kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
            kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        ],
        optionalConstraints: nil
    )

    fileprivate enum InternalError: Error {
        case failedToCreatePeerConnection
        case failedToCreateLocalSdpString
        case noPeerConnection(state: SdpExchangeState)
        case sdpExchangeTimedOut
        case peerConnectionTimedOut
        case peerDisconnected
        case internalConsistencyViolation(message: String)
    }

    fileprivate enum SdpExchangeState {
        case readyToStart
        case awaitingServerConfiguration
        case creatingPeerConnection
        case awaitingOffer
        case awaitingAnswer
        case sdpExchangeComplete
    }

    private var _sdpExchangeState = SdpExchangeState.readyToStart

    fileprivate enum SdpExchangeEvent {
        case serverConfigurationReceived(ServerConfiguration)
        case remoteSdpReceived(RTCSessionDescription)
    }

    // Internal state streams that must be created each connection session (when the task is
    // canceled or an error thrown, these get shut down)
    private var _sdpEventStream: AsyncStream<SdpExchangeEvent>?
    private var _sdpEventContinuation: AsyncStream<SdpExchangeEvent>.Continuation?
    private var _receivedIceCandidateStream: AsyncStream<RTCIceCandidate>?
    private var _receivedIceCandidateContinuation: AsyncStream<RTCIceCandidate>.Continuation?
    private var _peerConnectionStateStream: AsyncStream<RTCPeerConnectionState>?
    private var _peerConnectionStateContinuation: AsyncStream<RTCPeerConnectionState>.Continuation?

    // Outbound stream
    private let _isConnectedContinuation: AsyncStream<Bool>.Continuation
    private let _readyToConnectSignalContinuation: AsyncStream<Void>.Continuation
    private let _offerToSendContinuation: AsyncStream<String>.Continuation
    private let _iceCandidateToSendContinuation: AsyncStream<String>.Continuation
    private let _answerToSendContinuation: AsyncStream<String>.Continuation
    private let _cameraParamsToSendContinuation: AsyncStream<CameraParameters>.Continuation
    private let _textDataReceivedContinuation: AsyncStream<String>.Continuation

    fileprivate class RtcDelegateAdapter: NSObject {
        var client: AsyncWebRtcClient?
    }

    private let _rtcDelegateAdapter: RtcDelegateAdapter

    private var _task: Task<Bool, Never>?

    private var _pendingIceCandidates: [RTCIceCandidate] = []

    nonisolated private let _audioSession = RTCAudioSession.sharedInstance()
    nonisolated private let _audioQueue = DispatchQueue(label: "audioSessionConfiguration")

    private var _desiredCamera = CameraType.backDefault
    private var _desiredZoom: Float = 1.0

    private var _dataChannel: RTCDataChannel?
    private var _videoCapturer: RTCVideoCapturer?
    private var _localVideoTrack: RTCVideoTrack?
    private var _remoteVideoTrack: RTCVideoTrack?
    private var _isCapturing = false
    private var _camera: AVCaptureDevice?

    // MARK: API

    enum Role: String, Codable {
        case initiator = "initiator"
        case responder = "responder"
    }

    struct ServerConfiguration: Codable {
        struct Server: Codable {
            let url: String
            let user: String?
            let credential: String?
        }

        let role: Role
        let stunServers: [Server]
        let turnServers: [Server]
        let relayOnly: Bool
    }

    enum CameraType {
        case front
        case backDefault
        case backWide
        case backUltraWide
        case backTelephoto

        static func fromString(_ string: String) -> CameraType {
            switch string.lowercased() {
            case "front":
                return .front
            case "backdefault":
                return .backDefault
            case "backwide":
                return .backWide
            case "backultrawide":
                return .backUltraWide
            case "backtelephoto":
                return .backTelephoto
            default:
                return .backDefault
            }
        }
    }

    struct CameraParameters: Codable, CustomStringConvertible {
        let name: String
        let minZoom: Float
        let maxZoom: Float

        init(_ device: AVCaptureDevice) {
            name = device.localizedName
            minZoom = Float(device.minAvailableVideoZoomFactor)
            maxZoom = Float(device.maxAvailableVideoZoomFactor)
        }

        var description: String {
            return "\(name) zoom=[\(minZoom),\(maxZoom)]"
        }
    }

    /// Current peer connection status.
    let isConnected: AsyncStream<Bool>

    /// Event indicating that client is ready to connect and wants a `ReadyToConnectMessage` sent
    /// to signal server.
    let readyToConnectSignal: AsyncStream<Void>

    /// Offer SDP to send to remote peer via signal server.
    let offerToSend: AsyncStream<String>

    /// ICE candidates to send to remote peer via signal server.
    let iceCandidateToSend: AsyncStream<String>

    /// Answer SDP to send to remote peer via signal server.
    let answerToSend: AsyncStream<String>

    /// Parameters of camera being used to capture video. Published each time capture begins.
    let cameraParamsToSend: AsyncStream<CameraParameters>

    /// Text strings received on the data channel.
    let textDataReceived: AsyncStream<String>

    init() {
        (isConnected, _isConnectedContinuation) = Self.createStream()
        (readyToConnectSignal, _readyToConnectSignalContinuation) = Self.createStream()
        (offerToSend, _offerToSendContinuation) = Self.createStream()
        (iceCandidateToSend, _iceCandidateToSendContinuation) = Self.createStream()
        (answerToSend, _answerToSendContinuation) = Self.createStream()
        (cameraParamsToSend, _cameraParamsToSendContinuation) = Self.createStream()
        (textDataReceived, _textDataReceivedContinuation) = Self.createStream()

        // Delegate adapters -- needed to work around actor restrictions
        _rtcDelegateAdapter = RtcDelegateAdapter()
        _rtcDelegateAdapter.client = self
    }

    /// Runs the client forever. Continously attempts to form a connection.
    func run() async {
        while true {
            setSdpExchangeState(.readyToStart)
            let task = Task { return await runOneSession() }
            _task = task
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

    /// Cancel the current session, regardless of its state, and trigger another connection
    /// attempt. This is recommended when the signal server disconnects.
    func reconnect() async {
        log("Stopping current session...")
        _task?.cancel()
    }

    /// Add a renderer (e.g., created by the GUI layer), which WebRTC will use to render the remote
    /// video stream.
    /// - Parameter renderer: An RTC video renderer.
    func addRemoteVideoView(_ renderer: RTCVideoRenderer) async {
        _remoteVideoTrack?.add(renderer)
    }

    /// Remove a renderer that was previously added and is no longer valid to use. This should be
    /// safe to call even if the renderer was never added in the first place but this cannot be
    /// guaranteed and should be avoided if possible.
    /// - Parameter renderer: The RTC video renderer previously added.
    func removeRemoteVideoView(_ renderer: RTCVideoRenderer) async {
        _remoteVideoTrack?.remove(renderer)
    }

    /// Sets the desired camera to use for video input. If currently streaming, takes effect
    /// immediately.
    /// - Parameter cameraType: The camera to use. If no such camera exists on this model of iPhone,
    ///     will siliently fall back to the default (back) camera.
    func switchToCamera(_ cameraType: CameraType) async {
        _desiredCamera = cameraType

        if _isCapturing {
            log("Switching cameras...")
            stopCapture()
            startCapture()
        }
    }

    /// Sets the camera zoom factor. If currently streaming, takes effect immediately.
    /// - Parameter zoom: Zoom factor. Will be clamped against the valid zoom range for the camera.
    func setZoom(_ zoom: Float) async {
        _desiredZoom = zoom
        log("Zoom \(zoom) requested")
        setZoomFactor(for: _camera)
    }

    /// Notify client of configuration message received from signal server. This controls when the
    /// connection process starts as well as its behavior (e.g. offer vs. answer, ICE servers,
    /// etc.)
    /// - Parameter config: Configuration object received from signal server.
    func onServerConfigurationReceived(_ config: ServerConfiguration) async {
        _sdpEventContinuation?.yield(.serverConfigurationReceived(config))
    }

    /// Notify client of offer received from peer via signal server.
    /// - Parameter jsonString: The offer JSON object.
    func onOfferReceived(jsonString: String) async {
        log("Received offer")
        guard let offer = Offer.decode(jsonString: jsonString) else { return }
        let sdp = RTCSessionDescription(type: .offer, sdp: offer.sdp)
        _sdpEventContinuation?.yield(.remoteSdpReceived(sdp))
    }

    /// Notify client of answer received from peer via signal server.
    /// - Parameter jsonString: The answer JSON object.
    func onAnswerReceived(jsonString: String) async {
        log("Received answer")
        guard let answer = Answer.decode(jsonString: jsonString) else { return }
        let sdp = RTCSessionDescription(type: .answer, sdp: answer.sdp)
        _sdpEventContinuation?.yield(.remoteSdpReceived(sdp))
    }

    /// Notify client of ICE candidate received from peer via signal server.
    /// - Parameter jsonString: The ICE candidate JSON object.
    func onIceCandidateReceived(jsonString: String) async {
        guard let iceCandidate = ICECandidate.decode(jsonString: jsonString) else { return }
        let candidate = RTCIceCandidate(
            sdp: iceCandidate.candidate,
            sdpMLineIndex: iceCandidate.sdpMLineIndex,
            sdpMid: iceCandidate.sdpMid
        )
        _receivedIceCandidateContinuation?.yield(candidate)
    }

    /// Send text message over the data channel to the remote peer, if it is connected.
    /// - Parameter text: String to send.
    func sendTextData(_ text: String) async {
        let buffer = RTCDataBuffer(data: text.data(using: .utf8)!, isBinary: false)
        guard let dataChannel = _dataChannel else {
            logError("No data channel to send on")
            return
        }
        dataChannel.sendData(buffer)
    }

    // MARK: Internal methods

    private func runOneSession() async -> Bool {
        var peerConnection: RTCPeerConnection?

        defer {
            closeConnection(&peerConnection)
        }

        // Once the task dies, these streams cannot be reused, so must be created here each time
        (_sdpEventStream, _sdpEventContinuation) = Self.createStream()
        (_receivedIceCandidateStream, _receivedIceCandidateContinuation) = Self.createStream()
        (_peerConnectionStateStream, _peerConnectionStateContinuation) = Self.createStream()

        do {
            // State variables used only within our child tasks
            var sdpExchangeDeadline: Date?
            var initialConnectionFormedDeadline: Date?
            var isConnected = false

            // SDP exchange is the main task. ICE candidates have to be handled in parallel because
            // main task might be waiting while candidates trickle in. Anything driven by RTC state
            // changes should also be handled in parallel so as not to be blocked by the main SDP
            // task.
            try await withThrowingTaskGroup{ group in
                group.addTask { [weak self] in
                    try await self?.runSdpExchange(
                        for: &peerConnection,
                        isConnected: &isConnected,
                        sdpExchangeDeadline: &sdpExchangeDeadline,
                        initialConnectionFormedDeadline: &initialConnectionFormedDeadline
                    )
                }

                group.addTask { [weak self] in
                    try await self?.runIceCandidateProcessing(for: &peerConnection)
                }

                group.addTask { [weak self] in
                    try await self?.runConnectionMonitor(
                        isConnected: &isConnected,
                        initialConnectionFormedDeadline: &initialConnectionFormedDeadline
                    )
                }

                group.addTask { [weak self] in
                    try await self?.runTimeoutMonitor(
                        sdpExchangeDeadline: &sdpExchangeDeadline,
                        initialConnectionFormedDeadline: &initialConnectionFormedDeadline
                    )
                }

                sendReadyToConnectSignal()

                // Wait for all and rethrow any exceptions
                for try await _ in group {}
            }

            // Can only fall through here if canceled
            throw CancellationError()
        } catch is CancellationError {
            log("Session canceled")
            return true
        } catch {
            logError("Session aborted due to error: \(error)")
        }

        return false
    }

    private func setSdpExchangeState(_ newState: SdpExchangeState) {
        log("State: \(newState)")
        _sdpExchangeState = newState
    }

    private func sendReadyToConnectSignal() {
        _readyToConnectSignalContinuation.yield()
    }

    private func closeConnection(_ peerConnection: inout RTCPeerConnection?) {
        log("Closing peer connection")
        stopCapture()
        peerConnection?.close()
        peerConnection = nil
        _dataChannel = nil
        _videoCapturer = nil
        _localVideoTrack = nil
        _remoteVideoTrack = nil
        _isCapturing = false
        _camera = nil
    }

    /// Manages the main SDP exchange flow that is the backbone of the WebRTC state machine.
    private func runSdpExchange(for peerConnection: inout RTCPeerConnection?, isConnected: inout Bool, sdpExchangeDeadline: inout Date?, initialConnectionFormedDeadline: inout Date?) async throws {
        guard let sdpEventStream = _sdpEventStream else {
            throw InternalError.internalConsistencyViolation(message: "SDP event stream not available")
        }

        // Note: do not mistake this AsyncStream for a queue :)
        for await event in sdpEventStream {
            switch event {
            case .serverConfigurationReceived(let config):
                setSdpExchangeState(.creatingPeerConnection)

                if peerConnection != nil {
                    log("Unexpectedly received another server configuration. Restarting session state machine.")

                    // Peer must be retrying its connection, we need to restart. Because we
                    // received the server configuration, we cannot abort the process or we
                    // will end up causing a "livelock" by causing the signal server to send
                    // the configuration *again*, interrupting the peer and so forth.
                    closeConnection(&peerConnection)
                    sdpExchangeDeadline = nil
                    initialConnectionFormedDeadline = nil
                    if isConnected {
                        _isConnectedContinuation.yield(false)
                    }
                    isConnected = false
                }

                _pendingIceCandidates = []
                peerConnection = try await createConnection(with: config)

                if config.role == .initiator {
                    try await createAndSendOffer(for: peerConnection!)
                    setSdpExchangeState(.awaitingAnswer)
                } else {
                    setSdpExchangeState(.awaitingOffer)
                }

                sdpExchangeDeadline = Date.now.advanced(by: 10)

            case .remoteSdpReceived(let sdp):
                log("Handling remote SDP...")

                guard let peerConnection = peerConnection else {
                    throw InternalError.noPeerConnection(state: _sdpExchangeState)
                }

                try await peerConnection.setRemoteDescription(sdp)
                precondition(peerConnection.remoteDescription?.sdp != nil)

                // Once remote description is set, we can immediately process ICE candidates
                try await processPendingIceCandidates(for: peerConnection)

                if _sdpExchangeState == .awaitingOffer {
                    try await createAndSendAnswer(for: peerConnection)
                }

                setSdpExchangeState(.sdpExchangeComplete)

                // Once SDP exchanged, we expect connection to form
                sdpExchangeDeadline = nil
                initialConnectionFormedDeadline = Date.now.advanced(by: 10)

                // Process any other candidates that may have trickled in
                try await processPendingIceCandidates(for: peerConnection)
            }
        }
    }

    /// ICE candidates ought to be processed as soon as the remote SDP has been set but may arrive
    /// earlier and must be enqueued until it is possible to process them.
    private func runIceCandidateProcessing(for peerConnection: inout RTCPeerConnection?) async throws {
        guard let receivedIceCandidateStream = _receivedIceCandidateStream else {
            throw InternalError.internalConsistencyViolation(message: "ICE candidate stream not available")
        }

        for await candidate in receivedIceCandidateStream {
            if let peerConnection = peerConnection,
               peerConnection.remoteDescription != nil {
                // SDP exchange must be complete, we can accept ICE candidates
                try await processPendingIceCandidates(for: peerConnection)
                try await peerConnection.add(candidate)
                log("Added ICE candidate")
            } else {
                _pendingIceCandidates.append(candidate)
                log("Enqueued ICE candidate because state=\(_sdpExchangeState)")
            }
        }
    }

    /// We monitor the final peer connection state to decide when to begin transmitting media. We
    /// also present a simplified binary connection state to the outside world.
    private func runConnectionMonitor(isConnected: inout Bool, initialConnectionFormedDeadline: inout Date?) async throws {
        guard let peerConnectionStateStream = _peerConnectionStateStream else {
            throw InternalError.internalConsistencyViolation(message: "Peer connection state stream not available")
        }

        for await newState in peerConnectionStateStream {
            if newState == .connected {
                // Connected in time, cancel timeout check
                if initialConnectionFormedDeadline != nil {
                    log("Initial peer connection acknowledged")
                    initialConnectionFormedDeadline = nil
                }

                // Start media capture once connected
                startCapture()
            }

            // Pass along to outside subscriber if connected status changed
            let wasConnected = isConnected
            isConnected = newState == .connected
            if wasConnected != isConnected {
                _isConnectedContinuation.yield(isConnected)
            }

            // Detect connection failures
            if newState == .failed {
                if initialConnectionFormedDeadline != nil {
                    log("Connection never formed")
                } else {
                    log("Disconnected")
                }
                throw InternalError.peerDisconnected
            }
        }
    }

    /// Check for timeouts: SDP exchange should happen within a reasonable amount of time and then,
    /// an initial connection should be formed, too.
    private func runTimeoutMonitor(sdpExchangeDeadline: inout Date?, initialConnectionFormedDeadline: inout Date?) async throws {
        while true {
            if _sdpExchangeState == .awaitingAnswer || _sdpExchangeState == .awaitingOffer,
               let deadline = sdpExchangeDeadline {
                if Date.now >= deadline {
                    throw InternalError.sdpExchangeTimedOut
                }
            } else if _sdpExchangeState == .sdpExchangeComplete,
                      let deadline = initialConnectionFormedDeadline {
                if Date.now >= deadline {
                    throw InternalError.peerConnectionTimedOut
                }
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func createConnection(with serverConfig: ServerConfiguration) async throws -> RTCPeerConnection {
        log("Creating peer connection")

        let (config, constraints) = createConnectionConfiguration(with: serverConfig)

        guard let peerConnection = _factory.peerConnection(with: config, constraints: constraints, delegate: nil) else {
            throw InternalError.failedToCreatePeerConnection
        }

        peerConnection.delegate = _rtcDelegateAdapter

        // Create data channel
        if let dataChannel = peerConnection.dataChannel(forLabel: "chat", configuration: RTCDataChannelConfiguration()) {
            dataChannel.delegate = _rtcDelegateAdapter
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
        if _remoteVideoTrack == nil {
            logError("Remote video track not created")
        }

        return peerConnection
    }

    private func createConnectionConfiguration(with serverConfig: ServerConfiguration) -> (RTCConfiguration, RTCMediaConstraints) {
        let config = RTCConfiguration()
        config.bundlePolicy = .maxCompat                        // ?
        config.continualGatheringPolicy = .gatherContinually    // ?
        config.rtcpMuxPolicy = .require                         // ?
        config.tcpCandidatePolicy = .enabled
        config.keyType = .ECDSA
        config.iceTransportPolicy = serverConfig.relayOnly ? .relay : .all

        // ICE servers
        var iceServers: [RTCIceServer] = []
        addIceServers(to: &iceServers, from: serverConfig.stunServers)
        addIceServers(to: &iceServers, from: serverConfig.turnServers)
        config.iceServers = iceServers
        log("Using \(serverConfig.stunServers.count) STUN and \(serverConfig.turnServers.count) TURN servers")

        if serverConfig.relayOnly {
            log("Using relay-only ICE transport policy")
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                // Allegedly required for sharing streams with browsers
                "DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )

        return (config, constraints)
    }

    private func addIceServers(to iceServers: inout [RTCIceServer], from servers: [ServerConfiguration.Server]) {
        for server in servers {
            let iceServer = RTCIceServer(urlStrings: [server.url], username: server.user, credential: server.credential)
            iceServers.append(iceServer)
        }
    }

    private func processPendingIceCandidates(for peerConnection: RTCPeerConnection) async throws {
        guard peerConnection.remoteDescription?.sdp != nil else { return }
        var numProcessed = 0
        while let candidate = _pendingIceCandidates.first {
            try await peerConnection.add(candidate)
            numProcessed += 1
            _pendingIceCandidates.removeFirst()
        }
        log("Added \(numProcessed) ICE candidates from pending queue (state=\(_sdpExchangeState))")
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
        guard !_isCapturing else { return }
        guard let capturer = _videoCapturer as? RTCCameraVideoCapturer else { return }
        guard let camera = findCamera() else { return }
        let cameraParams = CameraParameters(camera)
        guard let format = (RTCCameraVideoCapturer.supportedFormats(for: camera).sorted { (fmt1, fmt2) -> Bool in
            let width1 = CMVideoFormatDescriptionGetDimensions(fmt1.formatDescription).width
            let width2 = CMVideoFormatDescriptionGetDimensions(fmt2.formatDescription).width
            return width1 < width2
        }).last,
        let fps = (format.videoSupportedFrameRateRanges.sorted { $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }

        setZoomFactor(for: camera)
        capturer.startCapture(with: camera, format: format, fps: Int(fps.maxFrameRate))
        switchAudioToSpeakerphone() // must configure audio here
        _isCapturing = true
        _camera = camera

        log("Started video capture: \(format.formatDescription)")
        log("Camera: \(cameraParams)")

        // Send camera parameters to signal server in case the other client wants them
        _cameraParamsToSendContinuation.yield(cameraParams)
    }

    private func setZoomFactor(for camera: AVCaptureDevice?) {
        guard let camera = camera else { return }
        do {
            try camera.lockForConfiguration()
            let zoom = CGFloat(_desiredZoom)
            camera.videoZoomFactor = max(min(zoom, camera.maxAvailableVideoZoomFactor), camera.minAvailableVideoZoomFactor)
            camera.unlockForConfiguration()
        } catch {
            logError("Unable to change zoom factor: \(error)")
        }
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

    private func createAndSendOffer(for peerConnection: RTCPeerConnection) async throws {
        let sdp = try await peerConnection.offer(for: _mediaConstraints)
        try await peerConnection.setLocalDescription(sdp)

        guard let sdpString = peerConnection.localDescription?.sdp else {
            throw InternalError.failedToCreateLocalSdpString
        }
        let container = String(data: try! JSONEncoder().encode(Offer(sdp: sdpString)), encoding: .utf8)!
        _offerToSendContinuation.yield(container)

        log("Sent offer")
    }

    private func createAndSendAnswer(for peerConnection: RTCPeerConnection) async throws {
        let sdp = try await peerConnection.answer(for: _mediaConstraints)
        try await peerConnection.setLocalDescription(sdp)

        guard let sdpString = peerConnection.localDescription?.sdp else {
            throw InternalError.failedToCreateLocalSdpString
        }
        let container = String(data: try! JSONEncoder().encode(Answer(sdp: sdpString)), encoding: .utf8)!
        _answerToSendContinuation.yield(container)

        log("Sent answer")
    }

    private static func createStream<T>() -> (AsyncStream<T>, AsyncStream<T>.Continuation) {
        var streamContinuation: AsyncStream<T>.Continuation?
        let stream = AsyncStream<T> { continuation in
            streamContinuation = continuation
        }
        return (stream, streamContinuation!)
    }
}

// MARK: RTC connection delegate

extension AsyncWebRtcClient.RtcDelegateAdapter: RTCPeerConnectionDelegate {
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
        Task { client?._iceCandidateToSendContinuation.yield(serialized) }
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
        Task { await client?._peerConnectionStateContinuation?.yield(newState) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
}

// MARK: Data channel delegate

extension AsyncWebRtcClient.RtcDelegateAdapter: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let stateToString: [RTCDataChannelState: String] = [
            .connecting: "connecting",
            .open: "open",
            .closed: "closed",
            .closing: "closing"
        ]
        let state = dataChannel.readyState
        let stateName = stateToString[state] ?? "unknown (\(state.rawValue))"
        log("Data channel state: \(stateName)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let textData = String(data: Data(buffer.data), encoding: .utf8) else { return }
        Task { client?._textDataReceivedContinuation.yield(textData) }
    }
}

extension AsyncWebRtcClient.InternalError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failedToCreatePeerConnection:
            return "Failed to create peer connection object"
        case .failedToCreateLocalSdpString:
            return "Failed to obtain local SDP and serialize it to a string"
        case .noPeerConnection(let state):
            return "No peer connection available in state '\(state)'"
        case .sdpExchangeTimedOut:
            return "SDP exchange process timed out"
        case .peerConnectionTimedOut:
            return "Connection to peer timed out and could not be established"
        case .peerDisconnected:
            return "Peer disconnected"
        case .internalConsistencyViolation(let message):
            return "Internal consistency violated: \(message)"
        }
    }
}

// MARK: WebRTC object serialization

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
            logError("Error decoding offer: \(error.localizedDescription)")
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
            logError("Error decoding answer: \(error.localizedDescription)")
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
            logError("Error decoding ICE candidate: \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: Logging

fileprivate func log(_ message: String) {
    print("[AsyncWebRtcClient] \(message)")
}

fileprivate func logError(_ message: String) {
    print("[AsyncWebRtcClient] Error: \(message)")
}
