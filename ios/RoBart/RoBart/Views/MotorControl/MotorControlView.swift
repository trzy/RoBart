//
//  MotorControlView.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import SwiftUI

struct MotorControlView: View {
    var body: some View {
        TabView {
            DPadMotorControlView()
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
    MotorControlView()
}
