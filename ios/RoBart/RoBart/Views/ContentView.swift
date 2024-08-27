//
//  ContentView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var _settings = Settings.shared

    var body: some View {
        NavigationView {
            ZStack {
                ARViewContainer().edgesIgnoringSafeArea(.all)
                VStack {
                    Spacer()
                    HStack() {
                        CollaborativeMappingStateView()
                    }
                }
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
        .onAppear {
        }
    }
}

#Preview {
    ContentView()
}
