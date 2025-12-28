//
//  SignalTransport.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 12/27/25.
//

import Combine
import Foundation
import Starscream

class SignalTransport: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var message: Message?

    private var _ws: WebSocket?
    private let _url = URL(string: "ws://192.168.0.128:8000/ws")!

    init() {
        let ws = WebSocket(request: URLRequest(url: _url))
        ws.delegate = self
        ws.connect()
        _ws = ws
    }

    /// Send a message to peers via the signaling transport.
    /// - Parameter message: The JSON-encoded message to send.
    func send(_ message: String) {
        _ws?.write(string: message)
    }

    private func reconnect() {
        _ws = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            print("[SignalTransport] Reconnecting...")
            let ws = WebSocket(request: URLRequest(url: _url))
            ws.delegate = self
            ws.connect()
            _ws = ws
        }
    }
}

extension SignalTransport: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        print("[SignaTransport] Event: \(event)")
        switch event {
        case .connected(_):
            print("[SignalTransport] WebSocket connected")
            let hello = HelloMessage(message: "Hello from iOS!")
            _ws?.write(string: hello.toJSON())
            isConnected = true

        case .text(let string):
            print("[SignalTransport] Received message: \(string)")

            if let message = Message.decode(from: string) {
                switch (message) {
                case .hello(let message):
                    // This is just an informational message, so we intercept it here
                    print("[SignalTransport] Peer said hello: \(message.message)")
                default:
                    // Forward the rest to the listener
                    self.message = message
                }
            } else {
                print("[SignalTransport] Ignoring unknown message")
            }

        case .disconnected(let reason, let code):
            print("[SignalTransport] WebSocket disconnected: \(reason) with code: \(code)")
            isConnected = false
            reconnect()

        case .error(let error):
            print("[SignalTransport] WebSocket error: \(error?.localizedDescription ?? "Unknown error")")

        case .cancelled:
            print("[SignalTransport] WebSocket cancelled")

        case .peerClosed:
            print("[SignalTransport] WebSocket disconnected: peer closed")
            isConnected = false
            reconnect()

        default:
            break
        }
    }
}
