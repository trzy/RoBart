//
//  RoBartApp.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
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

//
// TODO:
// -----
// - Configurable settings page for IP address to server
// - Second connect indicator for signal server
// - Render web cam on iOS
// - Audio!
//

import Combine
import SwiftUI

@main
struct RoBartApp: App {
    @StateObject private var _asyncWebRtcClient = AsyncWebRtcClient()
    @State var isConnected: Bool = false

    private let _transport = SignalTransport()
    private var _subscriptions = Set<AnyCancellable>()

    var body: some Scene {
        WindowGroup {
            ContentView(isConnected: $isConnected)
                .task {
                    await HoverboardController.shared.runTask()
                }
                .task {
                    // Run WebRTC on connection to signaling server
                    for await isConnected in _transport.$isConnected.values {
                        if isConnected {
                            print("Connected")
                            await _asyncWebRtcClient.run()
                        }
                    }
                }
                .task {
                    // Disconnect
                    for await isConnected in _transport.$isConnected.values {
                        if !isConnected {
                            print("Disconnected")
                            await _asyncWebRtcClient.stop()
                        }
                    }
                }
                .task {
                    for await connected in _asyncWebRtcClient.isConnected {
                        isConnected = connected
                    }
                }
                .task {
                    // When WebRTC is locally ready to establish a connection, let the signaling
                    // server know
                    for await _ in _asyncWebRtcClient.readyToConnectEvent {
                        _transport.send(ReadyToConnectMessage().toJSON())
                    }
                }
                .task {
                    for await sdp in _asyncWebRtcClient.offerToSend {
                        _transport.send(OfferMessage(data: sdp).toJSON())
                    }
                }
                .task {
                    for await sdp in _asyncWebRtcClient.answerToSend {
                        _transport.send(AnswerMessage(data: sdp).toJSON())
                    }
                }
                .task {
                    for await candidate in _asyncWebRtcClient.iceCandidateToSend {
                        _transport.send(ICECandidateMessage(data: candidate).toJSON())
                    }
                }
                .task {
                    for await message in _transport.$message.values {
                        switch (message) {
                        case .role(let message):
                            await _asyncWebRtcClient.onRoleAssigned(message.role == "initiator" ? .initiator : .responder)

                        case .iceCandidate(let message):
                            await _asyncWebRtcClient.onIceCandidateReceived(jsonString: message.data)

                        case .offer(let message):
                            await _asyncWebRtcClient.onOfferReceived(jsonString: message.data)

                        case .answer(let message):
                            await _asyncWebRtcClient.onAnswerReceived(jsonString: message.data)

                        default:
                            break;
                        }
                    }
                }
        }
    }
}
