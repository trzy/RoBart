//
//  HoverboardController.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/6/24.
//

import CoreBluetooth

enum HoverboardCommand {
    case drive(leftThrottle: Float, rightThrottle: Float)
}

class HoverboardController {
    static let shared = HoverboardController()

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

    var isConnected: Bool {
        return _connection != nil
    }

    static var isConnected: Bool {
        return shared.isConnected
    }

    static func send(_ command: HoverboardCommand) {
        shared.send(command)
    }

    private init() {
    }

    func runTask() async {
        while true {
            let peripheral = await findDevice()
            if let connection = await _ble.connect(to: peripheral) {
                log("Connection succeeded!")
                _connection = connection
                sendUpdateToBoard() // initial state
                do {
                    for try await data in connection.receivedData {
                        Util.hexDump(data)
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
        case .drive(let leftThrottle, let rightThrottle):
            _leftMotorThrottle = leftThrottle
            _rightMotorThrottle = rightThrottle
            log("Left=\(_leftMotorThrottle), Right=\(_rightMotorThrottle)")
        }
        sendUpdateToBoard()
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
