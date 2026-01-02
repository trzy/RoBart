//
//  HoverboardController.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//
//  Hoverboard Coordinate System
//  ----------------------------
//  - ARKit forward points *out* of the screen. The back camera's axis is -forward. This is
//    considered hoverboard forward (i.e., we always use -frame.camera.transform.forward).
//  - Turning the phone/hoverboard to the right (clockwise) is a negative rotation about the up
//    axis. That is, a forward vector of (0,0,-1) rotated -90 degrees becomes (1,0,0). Positive
//    rotation angles are counter-clockwise rotations: (0,0,-1) rotated by +90 degrees about up
//    axis becomes (-1,0,0).
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

import ARKit
import Combine
import CoreBluetooth

enum HoverboardCommand {
    case message(_ message: SimpleBinaryMessage)
    case drive(leftThrottle: Float, rightThrottle: Float)
    case rotateInPlace(steering: Float)
}

class HoverboardController {
    static let shared = HoverboardController()

    let hoverboardMessages = Util.AsyncStreamMulticaster<Data>()

    var isConnected: Bool {
        return _connection != nil
    }

    static var isConnected: Bool {
        return shared.isConnected
    }

    var maxThrottle: Float = 0.01

    var isMoving: Bool {
        return _leftMotorThrottle != 0 || _rightMotorThrottle != 0
    }

    private let _ble = AsyncBluetoothManager(
        service: CBUUID(string: "df72a6f9-a217-11ee-a726-a4b1c10ba08a"),
        rxCharacteristic: CBUUID(string: "9472ed74-a21a-11ee-91d6-a4b1c10ba08a"),
        txCharacteristic: CBUUID(string: "76b6bf48-a21a-11ee-8cae-a4b1c10ba08a")
    )

    private var _connection: AsyncBluetoothManager.Connection?

    private var _leftMotorThrottle: Float = 0.0 {
        didSet {
            _leftMotorThrottle = clamp(_leftMotorThrottle, min: -1.0, max: 1.0)
        }
    }

    private var _rightMotorThrottle: Float = 0.0 {
        didSet {
            _rightMotorThrottle = clamp(_rightMotorThrottle, min: -1.0, max: 1.0)
        }
    }

    private var _subscriptions = Set<AnyCancellable>()

    static func send(_ command: HoverboardCommand) {
        shared.send(command)
    }

    func runTask() async {
        // Bluetooth loop
        while true {
            let peripheral = await findDevice()
            if let connection = await _ble.connect(to: peripheral) {
                log("Connection succeeded!")
                _connection = connection
                sendUpdateToBoard() // initial state
                do {
                    for try await data in connection.receivedData {
                        // Send received message to any subscribers
                        hoverboardMessages.broadcast(data)
                    }
                } catch let error as AsyncBluetoothManager.StreamError {
                    log("Disconnected: \(error.localizedDescription)")
                } catch {
                    log("Error: \(error.localizedDescription)")
                }
            } else {
                log("Connection FAILED!")
            }
            _connection = nil
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func send(_ command: HoverboardCommand) {
        switch command {
        case .message(let message):
            // Send message immediately
            _connection?.send(message)

        case .drive(let leftThrottle, let rightThrottle):
            // Set new motor throttle values and send immediately
            _leftMotorThrottle = leftThrottle
            _rightMotorThrottle = rightThrottle
            //log("Left=\(_leftMotorThrottle), Right=\(_rightMotorThrottle)")
            sendUpdateToBoard()


        case .rotateInPlace(let steering):
            // Turn left (steering > 0): left=-steering, right=steering
            // Turn right (steering < 0): left=-steering, right=steering
            send(.drive(leftThrottle: -steering, rightThrottle: steering))
        }
    }

    private func findDevice() async -> CBPeripheral {
        while (true) {
            for await devices in _ble.discoveredDevices {
                if !devices.isEmpty {
                    log("Discovered devices:")
                    for device in devices {
                        log("  uuid=\(device.peripheral.identifier), rssi=\(device.rssi)")
                    }
                    if let device = devices.first {
                        return device.peripheral
                    }
                }
            }
        }
    }

    private func sendUpdateToBoard() {
        guard let connection = _connection else { return }
        let message = HoverboardMotorMessage(leftMotorThrottle: _leftMotorThrottle, rightMotorThrottle: _rightMotorThrottle)
        connection.send(message)
    }
}

fileprivate func log(_ message: String) {
    print("[HoverboardController] \(message)")
}
