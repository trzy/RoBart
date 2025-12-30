//
//  SignalTransport.swift
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
import Foundation
import Starscream

class SignalTransport: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var message: Message?

    private var _ws: WebSocket?
    private let _url = URL(string: "ws://192.168.0.128:8000/ws")!

    init() {
        if let url = Self.getUrl() {
            log("Connecting to: \(url.absoluteString)")
            let ws = WebSocket(request: URLRequest(url: url))
            ws.delegate = self
            ws.connect()
            _ws = ws
        }
    }

    /// Send a message to peers via the signaling transport.
    /// - Parameter message: The JSON-encoded message to send.
    func send(_ message: String) {
        _ws?.write(string: message)
    }

    private static func getUrl() -> URL? {
        guard let port = Settings.shared.webRtcServerPortNumber else { return nil }
        let address = "ws://\(Settings.shared.webRtcServerHostname):\(port)/ws"
        return URL(string: address)
    }

    private func reconnect() {
        _ws = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if let url = Self.getUrl() {
                log("Reconnecting to \(url.absoluteString)...")
                let ws = WebSocket(request: URLRequest(url: url))
                ws.delegate = self
                ws.connect()
                _ws = ws
            } else {
                logError("Unable to reconnect because WebRTC signal server address is invalid")
            }
        }
    }
}

extension SignalTransport: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        log("Event: \(event)")
        switch event {
        case .connected(_):
            log("WebSocket connected")
            let hello = HelloMessage(message: "Hello from iOS!")
            _ws?.write(string: hello.toJSON())
            isConnected = true

        case .text(let string):
            if let message = Message.decode(from: string) {
                switch (message) {
                case .hello(let message):
                    // This is just an informational message, so we intercept it here
                    log("Peer said hello: \(message.message)")
                default:
                    // Forward the rest to the listener
                    self.message = message
                }
            } else {
                logError("Ignoring invalid message")
            }

        case .disconnected(let reason, let code):
            log("WebSocket disconnected: \(reason) with code: \(code)")
            isConnected = false
            reconnect()

        case .error(let error):
            logError("WebSocket error: \(error?.localizedDescription ?? "Unknown error")")

        case .cancelled:
            log("WebSocket cancelled")

        case .peerClosed:
            log("WebSocket disconnected: peer closed")
            isConnected = false
            reconnect()

        default:
            break
        }
    }
}

fileprivate func log(_ message: String) {
    print("[SignalTransport] \(message)")
}

fileprivate func logError(_ message: String) {
    print("[SignalTransport] Error: \(message)")
}
