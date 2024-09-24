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
import Combine
import CoreBluetooth

enum HoverboardCommand {
    case message(_ message: SimpleBinaryMessage)
    case drive(leftThrottle: Float, rightThrottle: Float)
    case rotateInPlace(steering: Float)
    case rotateInPlaceBy(degrees: Float)
    case face(forward: Vector3)
    case driveForward(distance: Float)
    case driveTo(position: Vector3)
    case driveToFacing(position: Vector3, forward: Vector3)
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

    var orientationPIDGains = PID.Gains(Kp: 2.0, Ki: 1e-6, Kd: 0) {
        didSet {
            _orientationPID.gains = orientationPIDGains
        }
    }

    var positionPIDGains = PID.Gains(Kp: 1.0, Ki: 0, Kd: 0) {
        didSet {
            _positionPID.gains = positionPIDGains
        }
    }

    /// Maximum error in meters for position goal. Goal is considered achieved when both this is
    /// satisfied and the speed is below the threshold.
    var positionGoalTolerance: Float = 0.1

    /// Maximum speed at which the position goal is considered to be achieved provided that the
    /// distance is also within tolerance.
    var positionGoalMaximumSpeed: Float = 0.05

    /// Maximum error in degrees for orientation. Orientation goal is considered achieved when this
    /// condition is satisfied and the angular speed is sufficiently low.
    var orientationGoalTolerance: Float = 2.8

    /// Angular speed at which the orientation goal is considered to be achieved provided
    /// orientation is also within tolerance.
    var orientationGoalMaximumAngularSpeed: Float = 2.0

    var maxThrottle: Float = 0.01

    var isMoving: Bool {
        return _targetForward != nil || _targetPosition != nil || _leftMotorThrottle != 0 || _rightMotorThrottle != 0
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

    private var _targetForward: Vector3? {
        didSet {
            if let forward = _targetForward {
                _targetForward = forward.xzProjected.normalized
            }
        }
    }

    private var _targetPosition: Vector3? {
        didSet {
            if let position = _targetPosition {
                _targetPosition = position.xzProjected
            }
        }
    }

    private var _lastLoopTime: TimeInterval?
    private let _orientationPID: PID    // target and current forward angle in -> target angular velocity out
    private let _positionPID: PID       // target and current position in -> target forward velocity out
    private var _lastFrameTimestamp: TimeInterval?
    private let _angularVelocityFromSteering = Util.Interpolator(filename: "angular_velocity_kitchen_floor.txt")
    private let _steeringFromAngularVelocity = Util.Interpolator(filename: "angular_velocity_kitchen_floor.txt", columns: 2, columnX: 1, columnY: 0)

    private var _subscriptions = Set<AnyCancellable>()

    static func send(_ command: HoverboardCommand) {
        shared.send(command)
    }

    fileprivate init() {
        _orientationPID = PID(gains: orientationPIDGains)
        _positionPID = PID(gains: positionPIDGains)
    }

    func runTask() async {
        // Subscribe to frame updates from ARKit
        ARSessionManager.shared.frames.sink { [weak self] (frame: ARFrame) in
            self?.onFrame(frame)
        }.store(in: &_subscriptions)

        // Bluetooth connection to hoverboard only if we are the robot
        Settings.shared.$role.sink { [weak self] (role: Role) in
            if role != .robot {
                log("Disconnecting Bluetooth because we are no longer the robot")
                self?._ble.disconnect()
            }
        }.store(in: &_subscriptions)

        // Bluetooth loop
        while true {
            while Settings.shared.role != .robot {
                try? await Task.sleep(for: .seconds(5))
            }
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
        guard Settings.shared.role == .robot else { return }

        switch command {
        case .message(let message):
            // Send message immediately
            _connection?.send(message)

        case .drive(let leftThrottle, let rightThrottle):
            // Set new motor throttle values and send immediately
            _leftMotorThrottle = leftThrottle
            _rightMotorThrottle = rightThrottle
            log("Left=\(_leftMotorThrottle), Right=\(_rightMotorThrottle)")
            sendUpdateToBoard()

            // Disable PID control
            _targetForward = nil
            _targetPosition = nil

        case .rotateInPlace(let steering):
            // Turn left (steering > 0): left=-steering, right=steering
            // Turn right (steering < 0): left=-steering, right=steering
            send(.drive(leftThrottle: -steering, rightThrottle: steering))

            // Disable PID control
            _targetForward = nil
            _targetPosition = nil

        case .rotateInPlaceBy(let degrees):
            // New orientation set point
            let currentForward = -ARSessionManager.shared.transform.forward.xzProjected
            _targetForward = currentForward.rotated(by: degrees, about: .up)
            _targetPosition = nil   // no position target

        case .face(let forward):
            // New orientation set point
            _targetForward = forward.xzProjected
            _targetPosition = nil

        case .driveForward(let distance):
            // New position set point along current forward direction
            let currentForward = -ARSessionManager.shared.transform.forward.xzProjected.normalized
            _targetForward = currentForward
            _targetPosition = ARSessionManager.shared.transform.position.xzProjected + currentForward * distance

        case .driveTo(let position):
            _targetForward = nil
            _targetPosition = position.xzProjected

        case .driveToFacing(let position, let forward):
            _targetForward = forward.xzProjected
            _targetPosition = position.xzProjected
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
        guard Settings.shared.role == .robot else { return }

        guard let lastTimestamp = _lastLoopTime else {
            // Need to wait two consecutive frames to start measuring time
            _lastLoopTime = frame.timestamp
            return
        }

        // Adhere to control loop frequency
        let loopPeriod = TimeInterval(1.0 / controlLoopHz)
        let timeEpsilon = 1e-3
        guard frame.timestamp > (lastTimestamp + loopPeriod - timeEpsilon) else {
            return
        }
        _lastLoopTime = frame.timestamp

        let deltaTime = Float(frame.timestamp - lastTimestamp)
        let currentForward = -frame.camera.transform.forward.xzProjected.normalized
        let currentPosition = frame.camera.transform.position.xzProjected
        let speed = ARSessionManager.shared.speed
        let angularSpeed = ARSessionManager.shared.angularSpeed

        var leftMotorThrottle: Float = 0
        var rightMotorThrottle: Float = 0
        var pidEnabled = false

        // Orientation target: use target if one set, otherwise use vector toward target position if position set, otherwise none
        let targetForward = _targetForward != nil ? _targetForward! : (_targetPosition != nil ? (_targetPosition! - currentPosition).xzProjected.normalized : nil)
        if let targetForward = targetForward {
            var runOrientationPID = true

            // Orientation error: if heading to a position, we must keep the orientation PID active
            // but if only rotating, we stop when we hit our goal.
            let orientationErrorDegrees = Vector3.signedAngle(from: currentForward, to: targetForward, axis: Vector3.up)
            if _targetPosition == nil && abs(orientationErrorDegrees) <= abs(orientationGoalTolerance) && angularSpeed <= orientationGoalMaximumAngularSpeed {
                _targetForward = nil
                runOrientationPID = false
                leftMotorThrottle = 0
                rightMotorThrottle = 0
            }

            if runOrientationPID {
                // Orientation PID -> desired velocity
                let targetAngularVelocity = _orientationPID.update(deltaTime: deltaTime, error: orientationErrorDegrees)

                // Compute motor steering value based on desired velocity
                var steering = _steeringFromAngularVelocity.interpolate(x: targetAngularVelocity)
                steering = clamp(steering, min: -maxThrottle, max: maxThrottle)
                leftMotorThrottle += -steering
                rightMotorThrottle += steering

                log("Orientation: error=\(orientationErrorDegrees) angularSpeed=\(angularSpeed) targetVel=\(targetAngularVelocity) steer=\(steering)")
            }

            // Send update this frame (we had a target but may not anymore; we need to at least
            // send over the stop values)
            pidEnabled = true
        }

        // Forward position target
        if let targetPosition = _targetPosition {
            // PID measures linear distance along direction of travel (while orientation PID
            // continuously orients toward goal). We stop when the actual position is close enough.
            if (targetPosition - currentPosition).magnitude <= positionGoalTolerance && speed <= positionGoalMaximumSpeed {
                _targetPosition = nil
                _targetForward = nil
                leftMotorThrottle = 0
                rightMotorThrottle = 0
            }

            if let targetPosition = _targetPosition {
                // Position PID -> desired forward velocity
                let positionError = positionErrorAlongForwardAxis(currentPosition: currentPosition, targetPosition: targetPosition, currentForward: currentForward)
                let targetLinearVelocity = _positionPID.update(deltaTime: deltaTime, error: positionError)
                
                // Velocity -> throttle. If PID P gain is 1.0, this is simply a matter of rescaling to
                // allowed throttle range.
                let direction = sign(targetLinearVelocity)
                let throttle = abs(targetLinearVelocity).mapClamped(oldMin: 0, oldMax: 1, newMin: 0, newMax: maxThrottle)
                leftMotorThrottle += direction * throttle
                rightMotorThrottle += direction * throttle
                
                log("Position: error=\(positionError) speed=\(speed) targetVel=\(targetLinearVelocity) throttle=\(direction * throttle)")
            }

            // Send update this frame
            pidEnabled = true
        }

        // Send to board
        if pidEnabled {
            _leftMotorThrottle = leftMotorThrottle
            _rightMotorThrottle = rightMotorThrottle
            sendUpdateToBoard()
        }
    }

    private func estimateAngularVelocity(deltaTime: Float, lastForward: Vector3, currentForward: Vector3) -> Float {
        let degreesMoved = Vector3.signedAngle(from: lastForward.xzProjected, to: currentForward.xzProjected, axis: .up)
        let degreesPerSecond = degreesMoved / deltaTime
        return degreesPerSecond
    }

    private func positionErrorAlongForwardAxis(currentPosition: Vector3, targetPosition: Vector3, currentForward: Vector3) -> Float {
        let position = Vector3.dot(targetPosition - currentPosition, currentForward) * currentForward + currentPosition
        let delta = position - currentPosition
        let distance = delta.xzProjected.magnitude;
        let sign = sign(Vector3.dot(delta, currentForward))
        return sign * distance;
    }
}

fileprivate func log(_ message: String) {
    print("[HoverboardController] \(message)")
}
