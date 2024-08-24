//
//  Client.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/21/24.
//

import ARKit
import Combine
import Foundation

class Client {
    private var _task: Task<Void, Never>!
    private let _decoder = JSONDecoder()

    init() {
        _task = Task {
            await runTask()
        }
    }

    private func runTask() async {
        while true {
            do {
                let connection = try await AsyncTCPConnection(host: "192.168.0.123", port: 8000)
                connection.send(HelloMessage(message: "Hello from iOS!"))
                for try await receivedMessage in connection {
                    await handleMessage(receivedMessage, connection: connection)
                }
            } catch {
                log("Error: \(error.localizedDescription)")
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func handleMessage(_ receivedMessage: ReceivedJSONMessage, connection: AsyncTCPConnection) async {
        switch receivedMessage.id {
        case HelloMessage.id:
            if let msg = JSONMessageDeserializer.decode(receivedMessage, as: HelloMessage.self) {
                log("Hello received: \(msg.message)")
            }

        case DriveForDurationMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: DriveForDurationMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }

            log("Drive: \(msg.seconds) sec, \(msg.reverse ? "backward" : "forward"), speed=\(msg.speed)")

            let speed = msg.reverse ? -abs(msg.speed) : abs(msg.speed)
            HoverboardController.send(.drive(leftThrottle: speed, rightThrottle: speed))
            let initialPos = ARSessionManager.shared.transform.position

            await sleep(seconds: Double(msg.seconds))
            await stop()

            let finalPos = ARSessionManager.shared.transform.position
            let result = "Distance traveled: \((finalPos - initialPos).xzProjected.distance)"
            log(result)
            connection.send(LogMessage(text: result))

        case DriveForDistanceMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: DriveForDistanceMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }

            log("Drive: \(msg.meters) m, \(msg.reverse ? "backward" : "forward"), speed=\(msg.speed)")

            let speed = msg.reverse ? -abs(msg.speed) : abs(msg.speed)
            HoverboardController.send(.drive(leftThrottle: speed, rightThrottle: speed))

            // Drive until distance elapsed
            let initialPos = ARSessionManager.shared.transform.position
            repeat {
                _ = try? await ARSessionManager.shared.nextFrame()    // wait one frame
            } while (ARSessionManager.shared.transform.position - initialPos).xzProjected.distance < msg.meters

            await stop()

            // Measure actual distance traveled
            let distanceTraveled = "Distance traveled: \((ARSessionManager.shared.transform.position - initialPos).xzProjected.distance) m"
            connection.send(LogMessage(text: distanceTraveled))

        case WatchdogSettingsMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: WatchdogSettingsMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            let configMsg = HoverboardConfigMessage(watchdogEnabled: msg.enabled, watchdogSeconds: msg.timeoutSeconds)
            HoverboardController.send(.message(configMsg))

        case HoverboardRTTMeasurementMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: HoverboardRTTMeasurementMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            let responseMsg = await performRTTMeasurements(message: msg)
            connection.send(responseMsg)

        default:
            log("Error: Unhandled message: \(receivedMessage.id)")
            break
        }
    }

    private func stop() async {
        HoverboardController.send(.drive(leftThrottle: 0, rightThrottle: 0))
    }

    private func sleep(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func performRTTMeasurements(message msg: HoverboardRTTMeasurementMessage) async -> HoverboardRTTMeasurementMessage {
        // Perform a series of RTT measurements for the server to analyze. We sleep in between
        // successive samples in order to capture a representative variance in RTT.
        let (hoverboardMessages, handle) = HoverboardController.shared.hoverboardMessages.subscribe()
        var rttSeconds: [Double] = []

        for i in 0..<msg.numSamples {
            // Send ping
            let sentAt = Date.timeIntervalSinceReferenceDate
            HoverboardController.shared.send(.message(HoverboardPingMessage(timestamp: sentAt)))

            // Wait for pong
            while true {
                if let data = await hoverboardMessages.first(where: { _ in true}),
                   let pong = HoverboardPongMessage.deserialize(from: data) {
                    let receivedAt = Date.timeIntervalSinceReferenceDate
                    rttSeconds.append(receivedAt - pong.timestamp)
                    break
                }
            }

            // Delay until next test
            if i < (msg.numSamples - 1) {
                await sleep(seconds: msg.delay)
            }
        }

        HoverboardController.shared.hoverboardMessages.unsubscribe(handle)

        // Response to send back to server
        return HoverboardRTTMeasurementMessage(numSamples: msg.numSamples, delay: msg.delay, rttSeconds: rttSeconds)
    }
}

fileprivate func log(_ message: String) {
    print("[Client] \(message)")
}
