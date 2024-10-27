//
//  WatchConnectivityManager.swift
//  RoBart Remote Control Watch App
//
//  Created by Bart Trzynadlowski on 10/26/24.
//

import Foundation
import os
import WatchConnectivity

enum WatchMessageKey: String {
    case audio = "a"
}

enum WatchMessageID: UInt32 {
    case audioMessage = 0xa0
}

struct WatchAudioMessage: SimpleBinaryMessage {
    static let id = WatchMessageID.audioMessage.rawValue
    let chunkNumber: Int32
    let finished: Bool
    let samples: Data
}

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set) var receivedMessage: [WatchMessageKey: Data] = [:]
    @Published private(set) var isConnected = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else {
            fatalError("Watch connectivity not supported")
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendMessage(_ values: [WatchMessageKey: Data]) {
        if isConnected {
            // Convert keys to strings
            var validatedMessage: [String: Data] = [:]
            for (key, value) in values {
                validatedMessage[key.rawValue] = value
            }

            // Send
            WCSession.default.sendMessage(validatedMessage as [String : Any], replyHandler: nil) { error in
                log("Failed to send message via WatchConnectivity: \(error.localizedDescription)")
            }
        }
    }

    func sendMessage(key: WatchMessageKey, value: SimpleBinaryMessage) {
        sendMessage([ key: value.serialize() ])
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = WCSession.default.isReachable
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if let error = error {
            log("Activation error: \(error.localizedDescription) (activationState=\(activationState))")
        } else {
            log("Activation completed (activationState=\(activationState))")
        }
    }

    #if os(iOS) // these are not available on watchOS
    func sessionDidBecomeInactive(_ session: WCSession) {
        log("Session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        log("Session deactivated")
    }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async { [weak self] in
            // Discard any key that is not a message ID and any value that is not Data
            var validatedMessage: [WatchMessageKey: Data] = [:]
            for (key, value) in message {
                guard let key = WatchMessageKey(rawValue: key),
                      let value = value as? Data else { continue }
                validatedMessage[key] = value
            }

            // Broadcast message if it contains anything
            if validatedMessage.count > 0 {
                self?.receivedMessage = validatedMessage
            }
        }
    }
}

fileprivate let _logger = Logger()

fileprivate func log(_ message: String) {
    _logger.notice("[WatchConnectivityManager] \(message, privacy: .public)")
}
