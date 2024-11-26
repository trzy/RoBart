//
//  HoverboardControlView.swift
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
