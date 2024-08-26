//
//  ContentView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var _settings = Settings.shared

    var body: some View {
        NavigationView {
            VStack {
                ARViewContainer().edgesIgnoringSafeArea(.all)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink {
                        HoverboardControlView()
                    } label: {
                        Image(systemName: "car.front.waves.down")
                            .imageScale(.large)
                    }
                    .disabled(_settings.role != .robot)

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
    }
}

#Preview {
    ContentView()
}
