//
//  SettingsView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var _settings = Settings.shared

    private let _isRobot = Binding<Bool>(
        get: { Settings.shared.role == .robot },
        set: { (value: Bool) in }
    )

    var body: some View {
        NavigationView {
            VStack {
                Text("Settings")
                    .font(.largeTitle)

                Divider()

                VStack {
                    List {
                        Picker("Role", selection: $_settings.role) {
                            Text("Robot").tag(Role.robot)
                            Text("Handheld").tag(Role.handheld)
                        }

                        LabeledContent {
                            TextField("Anthropic API Key", text: $_settings.anthropicAPIKey, prompt: Text("..."))
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("Anthropic API Key")
                        }

                        // How the "drive-to" button functions
                        Picker("Drive-To Behavior", selection: $_settings.driveToButtonUsesNavigation) {
                            Text("Uses Navigation").tag(true)
                            Text("Drive Straight").tag(false)
                        }
                        .disabled(_isRobot.wrappedValue)
                    }
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
