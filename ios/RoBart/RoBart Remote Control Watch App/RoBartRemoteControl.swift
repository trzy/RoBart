//
//  RoBartRemoteControl.swift
//  RoBart Remote Control Watch App
//
//  Created by Bart Trzynadlowski on 10/26/24.
//

import SwiftUI

@main
struct RoBartRemoteControl: App {
    private let _audioRecorder = AudioRecorder()

    var body: some Scene {
        WindowGroup {
            ContentView(audioRecorder: _audioRecorder)
        }
    }
}
