//
//  RoBartApp.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI
import WebRTCVAD

@main
struct RoBartApp: App {
    private let _client = Client()
    private let _peerManager = PeerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView(client: _client)
                .task {
                    await HoverboardController.shared.runTask()
                }
                .task {
                    await NavigationController.shared.runTask()
                }
        }
    }
}
