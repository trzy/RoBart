//
//  HoverboardControlView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

struct HoverboardControlView: View {
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
    }
}

#Preview {
    HoverboardControlView()
}
