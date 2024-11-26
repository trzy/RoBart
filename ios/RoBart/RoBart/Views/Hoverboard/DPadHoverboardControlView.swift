//
//  DPadHoverboardControlView.swift
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

struct DPadHoverboardControlView: View {
    @State private var speed: Float = 0.0
    @State private var leftSpeed: Float = 0.0
    @State private var rightSpeed: Float = 0.0
    @State private var usingEqualSpeed = true

    @State private var _leftThrottle: Float = 0.0
    @State private var _rightThrottle: Float = 0.0

    var body: some View {
        VStack {
            Text("D-Pad")
                .font(.largeTitle)

            Spacer()

            HStack {
                Spacer()

                // Forward
                Button(action: {}, label: {
                    TriangleShape(direction: .up)
                        .fill(Color.green)
                })
                .padding()
                .onTouchDown {
                    print("Left motor: \(leftSpeed)")
                    print("Right motor: \(rightSpeed)")
                    _leftThrottle = leftSpeed
                    _rightThrottle = rightSpeed
                    sendToMotors()
                }
                .onTouchUp {
                    print("Left motor: 0")
                    print("Right motor: 0")
                    _leftThrottle = 0
                    _rightThrottle = 0
                    sendToMotors()
                }

                Spacer()
            }
            .frame(maxWidth: 200)

            HStack {
                // Turn left
                Button(action: {}, label: {
                    TriangleShape(direction: .left)
                        .fill(Color.green)
                })
                .padding()
                .onTouchDown {
                    print("Left motor: -\(leftSpeed)")
                    print("Right motor: \(rightSpeed)")
                    _leftThrottle = -leftSpeed
                    _rightThrottle = rightSpeed
                    sendToMotors()
                }
                .onTouchUp {
                    print("Left motor: 0")
                    print("Right motor: 0")
                    _leftThrottle = 0
                    _rightThrottle = 0
                    sendToMotors()
                }

                // Turn right
                Button(action: {}, label: {
                    TriangleShape(direction: .right)
                        .fill(Color.green)
                })
                .padding()
                .onTouchDown {
                    print("Left motor: \(leftSpeed)")
                    print("Right motor: -\(rightSpeed)")
                    _leftThrottle = leftSpeed
                    _rightThrottle = -rightSpeed
                    sendToMotors()
                }
                .onTouchUp {
                    print("Left motor: 0")
                    print("Right motor: 0")
                    _leftThrottle = 0
                    _rightThrottle = 0
                    sendToMotors()
                }
            }
            .frame(maxWidth: 350, maxHeight: 200)

            HStack {
                Spacer()

                // Backward
                Button(action: {}, label: {
                    TriangleShape(direction: .down)
                        .fill(Color.green)
                })
                .padding()
                .onTouchDown {
                    print("Left motor: -\(leftSpeed)")
                    print("Right motor: -\(rightSpeed)")
                    _leftThrottle = -leftSpeed
                    _rightThrottle = -rightSpeed
                    sendToMotors()
                }
                .onTouchUp {
                    print("Left motor: 0")
                    print("Right motor: 0")
                    _leftThrottle = 0
                    _rightThrottle = 0
                    sendToMotors()
                }

                Spacer()
            }
            .frame(maxWidth: 200)

            // Unified speed for both left and right motors
            VStack {
                Slider(
                    value: $speed,
                    in: 0...0.2,
                    onEditingChanged: { editing in
                        if editing {
                            usingEqualSpeed = true
                        }
                    }
                )
                HStack {
                    Spacer()
                    Text("Speed")
                    Spacer()
                    Text("\(speed, specifier: "%.2f")")
                    Spacer()
                }
                .opacity(usingEqualSpeed ? 1.0 : 0.5)
            }
            .padding()
            .frame(maxWidth: 600)

            // Left motor speed
            VStack {
                Slider(
                    value: $leftSpeed,
                    in: 0...0.2,
                    onEditingChanged: { editing in
                        if editing {
                            // No longer using a unified speed
                            usingEqualSpeed = false
                        }
                    }
                )
                HStack {
                    Spacer()
                    Text("Left Motor Speed")
                    Spacer()
                    Text("\(leftSpeed, specifier: "%.2f")")
                    Spacer()
                }
                .opacity(usingEqualSpeed ? 0.5 : 1.0)
            }
            .padding()
            .frame(maxWidth: 600)

            // Right motor speed
            VStack {
                Slider(
                    value: $rightSpeed,
                    in: 0...0.2,
                    onEditingChanged: { editing in
                        if editing {
                            // No longer using a unified speed
                            usingEqualSpeed = false
                        }
                    }
                )
                HStack {
                    Spacer()
                    Text("Right Motor Speed")
                    Spacer()
                    Text("\(rightSpeed, specifier: "%.2f")")
                    Spacer()
                }
                .opacity(usingEqualSpeed ? 0.5 : 1.0)
            }
            .padding()
            .frame(maxWidth: 600)

            Spacer()
        }
        .onChange(of: speed) { oldValue, newValue in
            // When unified speed changes, must update slider values for left and right
            leftSpeed = newValue
            rightSpeed = newValue
        }
    }

    private func sendToMotors() {
        if Settings.shared.role == .robot {
            // We are the robot
            HoverboardController.shared.send(.drive(leftThrottle: _leftThrottle, rightThrottle: _rightThrottle))
        } else {
            // Send to the robot
            PeerManager.shared.send(PeerMotorMessage(leftMotorThrottle: _leftThrottle, rightMotorThrottle: _rightThrottle), toPeersWithRole: .robot, reliable: true)
        }
    }
}

#Preview {
    DPadHoverboardControlView()
}
