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

import ARKit
import CoreBluetooth

enum HoverboardCommand {
    case message(_ message: SimpleBinaryMessage)
    case drive(leftThrottle: Float, rightThrottle: Float)
    case rotate(degrees: Float)
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

    var controlLoopHz: Float = 20 {
        didSet {
            controlLoopHz = max(1, min(30, controlLoopHz))
        }
    }

    var orientationKp: Float = 0.6 {
        didSet {
            _orientationPID?.Kp = orientationKp
        }
    }

    var orientationKi: Float = 0 {
        didSet {
            _orientationPID?.Ki = orientationKi
        }
    }

    var orientationKd: Float = 0 {
        didSet {
            _orientationPID?.Kd = orientationKd
        }
    }

    var angularVelocityKp: Float = 2.5 {
        didSet {
            _angularVelocityPID?.Kp = angularVelocityKp
        }
    }

    var angularVelocityKi: Float = 0 {
        didSet {
            _angularVelocityPID?.Ki = angularVelocityKi
        }
    }

    var angularVelocityKd: Float = 1.0 {
        didSet {
            _angularVelocityPID?.Kd = angularVelocityKd
        }
    }

    var maxThrottle: Float = 0.02
    var minThrottle: Float = 0

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

    private var _targetForward: Vector3? {
        didSet {
            if let forward = _targetForward {
                _targetForward = forward.normalized
            }
        }
    }

    private var _pidControlEnabled: Bool {
        get {
            return _orientationPID != nil && _angularVelocityPID != nil
        }

        set {
            if newValue {
                // Instantiate new PID controllers if they don't exist; reset existing ones
                if _orientationPID == nil {
                    _orientationPID = PID(Kp: orientationKp, Ki: orientationKi, Kd: orientationKd)
                }
                if _angularVelocityPID == nil {
                    _angularVelocityPID = PID(Kp: angularVelocityKp, Ki: angularVelocityKi, Kd: angularVelocityKd)
                }
                _orientationPID?.reset()
                _angularVelocityPID?.reset()
            } else {
                // Disable PID control by destroying the controller objects
                _orientationPID = nil
                _angularVelocityPID = nil
            }
        }
    }

    private var _lastLoopTime: TimeInterval?
    private var _orientationPID: PID?       // target and current forward angle in -> target angular velocity out
    private var _angularVelocityPID: PID?   // target and current angular velocity in -> throttle out

    private var _lastFrameTimestamp: TimeInterval?
    private var _lastForward: Vector3?

    static func send(_ command: HoverboardCommand) {
        shared.send(command)
    }

    private init() {
    }

    func runTask() async {
        // Subscribe to frame updates from ARKit
        let subscription = ARSessionManager.shared.frames.sink { [weak self] (frame: ARFrame) in
            self?.onFrame(frame)
        }

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
            _pidControlEnabled = false
            _leftMotorThrottle = leftThrottle
            _rightMotorThrottle = rightThrottle
            log("Left=\(_leftMotorThrottle), Right=\(_rightMotorThrottle)")
            sendUpdateToBoard()

        case .rotate(let degrees):
            // New orientation set point
            let currentForward = -ARSessionManager.shared.transform.forward.xzProjected
            _targetForward = currentForward.rotated(by: degrees, about: .up)
            _pidControlEnabled = true
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

    private func onFrame(_ frame: ARFrame) {
        guard let lastTimestamp = _lastLoopTime,
              let lastForward = _lastForward else {
            // Need to wait two consecutive frames to start measuring time
            _lastLoopTime = frame.timestamp
            _lastForward = -frame.camera.transform.forward  // -forward is out of back camera (hoverboard forward)
            return
        }

        // Adhere to control loop frequency
        let loopPeriod = TimeInterval(1.0 / controlLoopHz)
        let timeEpsilon = 1e-3
        guard frame.timestamp > (lastTimestamp + loopPeriod - timeEpsilon) else {
            return
        }

        guard _pidControlEnabled,
              let orientationPID = _orientationPID,
              let angularVelocityPID = _angularVelocityPID,
              let targetForward = _targetForward else {
            _orientationPID?.reset()
            _angularVelocityPID?.reset()
            return
        }

        // Cascaded PID for orientation. Steering sign corresponds to rotation angle required to
        // align toward target forward. That is, positive -> counter-clockwise (turn left) and
        // negative -> clockwise (turn right).
        let deltaTime = Float(frame.timestamp - lastTimestamp)
        let currentForward = -frame.camera.transform.forward
        let orientationErrorDegrees = Vector3.signedAngle(from: currentForward, to: targetForward, axis: Vector3.up)
        let currentAngularVelocity = estimateAngularVelocity(deltaTime: deltaTime, lastForward: lastForward, currentForward: currentForward)
        let targetAngularVelocity = orientationPID.update(deltaTime: deltaTime, error: orientationErrorDegrees)
        let steering = angularVelocityPID.update(deltaTime: deltaTime, error: targetAngularVelocity - currentAngularVelocity)


        log("CurrentForward=\(currentForward) TargetForward=\(targetForward)")

        let (leftSteering, rightSteering) = steeringAmountToThrottle(steering)
        _leftMotorThrottle = leftSteering
        _rightMotorThrottle = rightSteering

        log("OrientError=\(orientationErrorDegrees) AngVel=\(currentAngularVelocity) TargetAngVel=\(targetAngularVelocity)")
        log("Steering=\(steering), L,R=(\(leftSteering),\(rightSteering)) Throttle=(\(_leftMotorThrottle),\(_rightMotorThrottle))")

        sendUpdateToBoard()
    }

    private func estimateAngularVelocity(deltaTime: Float, lastForward: Vector3, currentForward: Vector3) -> Float {
        let degreesMoved = Vector3.signedAngle(from: lastForward.xzProjected, to: currentForward.xzProjected, axis: .up)
        let degreesPerSecond = degreesMoved / deltaTime
        return degreesPerSecond
    }

    private func steeringAmountToThrottle(_ steeringValue: Float) -> (Float, Float) {
        let sign = steeringValue >= 0 ? Float(1.0) : Float(-1.0)
        let steering = sign * abs(steeringValue).mapClamped(oldMin: 0, oldMax: 180.0, newMin: minThrottle, newMax: maxThrottle)

        /*
         * Steering Value -> Turn Direction -> Left, Right
         * -----------------------------------------------
         *      -1              Right           +1, -1
         *      0               Idle            0, 0
         *      +1              Left            -1, +1
         */

        let leftSteering = -steering
        let rightSteering = steering
        return (leftSteering, rightSteering)
    }
}

fileprivate func log(_ message: String) {
    print("[HoverboardController] \(message)")
}
