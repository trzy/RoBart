//
//  RoBartApp.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

@main
struct RoBartApp: App {
    private let _audio = AudioManager.shared
    private let _brain = Brain.shared
    private let _client = Client.shared
    private let _peerManager = PeerManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await HoverboardController.shared.runTask()
                }
                .task {
                    await NavigationController.shared.runTask()
                }
        }
    }
}
