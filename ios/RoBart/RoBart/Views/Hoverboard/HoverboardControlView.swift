//
//  HoverboardControlView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

struct HoverboardControlView: View {
    @State private var _brainEnabledState = false

    var body: some View {
        TabView {
            DPadHoverboardControlView()
                .tabItem {
                    Label("Directional", systemImage: "dpad")
                }
            PerMotorControlView()
                .tabItem {
                    Label("Per-Motor", systemImage: "arrow.up.arrow.down")
                }
        }
        .onAppear {
            _brainEnabledState = Brain.shared.enabled
            Brain.shared.enabled = false
        }
        .onDisappear {
            Brain.shared.enabled = _brainEnabledState
        }
    }
}

#Preview {
    HoverboardControlView()
}
