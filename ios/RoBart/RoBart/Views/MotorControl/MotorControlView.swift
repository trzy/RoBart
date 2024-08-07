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
            PerMotorControlView()
                .tabItem {
                    Label("Per-Motor", systemImage: "arrow.up.arrow.down")
                }
            DirectionalMotorControlView()
                .tabItem {
                    Label("Directional", systemImage: "dpad")
                }
        }
    }
}

#Preview {
    MotorControlView()
}
