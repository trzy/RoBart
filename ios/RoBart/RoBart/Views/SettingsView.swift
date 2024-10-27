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

                        Toggle("Watch Voice Input", isOn: $_settings.watchEnabled)

                        Picker("AI Model", selection: $_settings.model) {
                            Text("Claude 3.5 Sonnet").tag(Brain.Model.claude35Sonnet)
                            Text("GPT-4 Turbo").tag(Brain.Model.gpt4Turbo)
                            Text("GPT-4o").tag(Brain.Model.gpt4o)
                        }

                        LabeledContent {
                            TextField("Anthropic API Key", text: $_settings.anthropicAPIKey, prompt: Text("..."))
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("Anthropic API Key")
                        }

                        LabeledContent {
                            TextField("OpenAI API Key", text: $_settings.openAIAPIKey, prompt: Text("..."))
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("OpenAI API Key")
                        }

                        LabeledContent {
                            TextField("Deepgram API Key", text: $_settings.deepgramAPIKey, prompt: Text("..."))
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Text("Deepgram API Key")
                        }

                        // How the "drive-to" button functions
                        Picker("Drive-To Behavior", selection: $_settings.driveToButtonUsesNavigation) {
                            Text("Uses Navigation").tag(true)
                            Text("Drive Straight").tag(false)
                        }
                        .disabled(_isRobot.wrappedValue)

                        // How far behind a person RoBart should follow in follower mode
                        VStack {
                            Slider(
                                value: $_settings.followDistance,
                                in: 1...4
                            )
                            HStack {
                                Spacer()
                                Text("Follow Distance (meters)")
                                Spacer()
                                Text("\(_settings.followDistance, specifier: "%.2f")")
                                Spacer()
                            }
                        }
                        .padding()
                        .frame(maxWidth: 600)

                        // Maximum distance to detect people at
                        VStack {
                            Slider(
                                value: $_settings.maxPersonDistance,
                                in: 2...8
                            )
                            HStack {
                                Spacer()
                                Text("Maximum Person Distance (meters)")
                                Spacer()
                                Text("\(_settings.maxPersonDistance, specifier: "%.2f")")
                                Spacer()
                            }
                        }
                        .padding()
                        .frame(maxWidth: 600)

                        // Rate of people detection when running in person follower mode
                        VStack {
                            Slider(
                                value: $_settings.personDetectionHz,
                                in: 0.5...8
                            )
                            HStack {
                                Spacer()
                                Text("Person Detection Frequency (Hz)")
                                Spacer()
                                Text("\(_settings.personDetectionHz, specifier: "%.1f")")
                                Spacer()
                            }
                        }
                        .padding()
                        .frame(maxWidth: 600)

                        // Whether to record videos for each task
                        Toggle("Record Videos", isOn: $_settings.recordVideos)

                        // Whether to annotate the recorded videos with augmentations
                        Toggle("Annotate Videos", isOn: $_settings.annotateVideos)
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
