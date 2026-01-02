//
//  ContentView.swift
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

import Combine
import SwiftUI

struct ContentView: View {
    @Binding var isConnected: Bool

    @State private var _subscription: Cancellable?
    @EnvironmentObject private var _asyncWebRtcClient: NewWebRtcClient

    var body: some View {
        GeometryReader { reader in
            NavigationView {
                ZStack {
                    if isConnected {
                        // We use isConnected to detect a change in connection state that
                        // implies a new connection and video track. We build a new video view each
                        // time by instantiating the view below.
                        RemoteVideoView(size: reader.size, client: _asyncWebRtcClient)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Image(systemName: isConnected ? "network" : "network.slash")
                            .foregroundStyle(isConnected ? .primary : Color.red)
                        Spacer()
                        NavigationLink {
                            HoverboardControlView()
                        } label: {
                            Image(systemName: "car.front.waves.down")
                                .imageScale(.large)
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gear")
                                .imageScale(.large)
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)    // prevent landscape mode column behavior
            .onAppear {
            }
        }
    }
}

fileprivate func log(_ message: String) {
    print("[ContentView] \(message)")
}

#Preview {
    ContentView(isConnected: .constant(true))
}
