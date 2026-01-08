//
//  OnTouch.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//
//  Provides .onTouchDown and .onTouchUp modifiers.
//  See: https://stackoverflow.com/questions/58784684/how-do-you-detect-a-swiftui-touchdown-event-with-no-movement-or-duration
//  And: https://www.hackingwithswift.com/quick-start/swiftui/how-to-make-swiftui-modifiers-safer-to-use-with-warn-unqualified-access
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

extension View {
    @warn_unqualified_access
    func onTouchDown(completion: @escaping () -> Void) -> some View {
        modifier(OnTouchDownGestureModifier(completion: completion))
    }

    @warn_unqualified_access
    func onTouchUp(completion: @escaping () -> Void) -> some View {
        modifier(OnTouchUpGestureModifier(completion: completion))
    }
}

struct OnTouchDownGestureModifier: ViewModifier {
    @State private var tapped = false
    private let _completion: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !self.tapped {
                            self.tapped = true
                            self._completion()
                        }
                    }
                    .onEnded { _ in
                        self.tapped = false
                    }
            )
    }

    init(completion: @escaping () -> Void) {
        _completion = completion
    }
}

struct OnTouchUpGestureModifier: ViewModifier {
    @State private var tapped = false
    private let _completion: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !self.tapped {
                            self.tapped = true
                        }
                    }
                    .onEnded { _ in
                        self.tapped = false
                        self._completion()
                    }
            )
    }

    init(completion: @escaping () -> Void) {
        _completion = completion
    }
}
