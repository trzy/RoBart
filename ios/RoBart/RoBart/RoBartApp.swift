//
//  RoBartApp.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

@main
struct RoBartApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await MotorController.shared.runTask()
                }
        }
    }
}
