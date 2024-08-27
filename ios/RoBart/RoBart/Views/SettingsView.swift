//
//  SettingsView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var _settings = Settings.shared

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
                            Text("Phone").tag(Role.phone)
                        }
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
