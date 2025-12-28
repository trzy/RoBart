//
//  SettingsView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 12/28/25.
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
                        VStack(alignment: .leading) {
                            Text("WebRTC Signaling Server Hostname")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "e.g., 192.168.0.100",
                                text: $_settings.webRtcServerHostname
                            )
                        }
                        VStack(alignment: .leading) {
                            Text("WebRTC Signaling Server Port")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(
                                "e.g., 8000",
                                text: $_settings.webRtcServerPort
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
