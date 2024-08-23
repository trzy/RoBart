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
