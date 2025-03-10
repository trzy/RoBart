//
//  Client.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/21/24.
//
//  Handles communication with debug server and some communication with peers.
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
import Foundation
import MultipeerConnectivity

class Client: ObservableObject {
    static let shared = Client()

    @Published var robotOccupancyMapImage: UIImage?

    private var _task: Task<Void, Never>!
    private var _connection: AsyncTCPConnection?
    private let _decoder = JSONDecoder()
    private var _subscription: Cancellable?

    private init() {
        _subscription = PeerManager.shared.$receivedMessage.sink { [weak self] (received: (peerID: MCPeerID, data: Data)?) in
            guard let received = received else { return }
            self?.handlePeerMessage(received.data, from: received.peerID)
        }

        _task = Task {
            await runTask()
        }
    }

    func send(_ message: JSONMessage) {
        _connection?.send(message)
    }

    func stopRobot() {
        log("Stopping robot...")
        HoverboardController.shared.send(.drive(leftThrottle: 0, rightThrottle: 0))
        NavigationController.shared.stopNavigation()
    }

    private func runTask() async {
        while true {
            do {
                let connection = try await AsyncTCPConnection(host: "192.168.0.123", port: 8000)
                _connection = connection
                connection.send(HelloMessage(message: "Hello from iOS!"))
                for try await receivedMessage in connection {
                    await handleDebugServerMessage(receivedMessage, connection: connection)
                }
            } catch {
                log("Error: \(error.localizedDescription)")
                _connection = nil
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func handlePeerMessage(_ data: Data, from peerID: MCPeerID) {
        if let msg = PeerMotorMessage.deserialize(from: data) {
            log("Received motor message from peer")
            HoverboardController.send(.drive(leftThrottle: msg.leftMotorThrottle, rightThrottle: msg.rightMotorThrottle))
        } else if let _ = PeerStopMessage.deserialize(from: data) {
            log("Received stop message from peer")
            stopRobot()
        } else if let msg = PeerOccupancyMessage.deserialize(from: data) {
            log("Received occupancy map message from peer")
            renderOccupancyMap(from: msg)
        }
    }

    private func handleDebugServerMessage(_ receivedMessage: ReceivedJSONMessage, connection: AsyncTCPConnection) async {
        guard Settings.shared.role == .robot else { return }

        switch receivedMessage.id {
        case HelloMessage.id:
            if let msg = JSONMessageDeserializer.decode(receivedMessage, as: HelloMessage.self) {
                log("Hello received: \(msg.message)")
            }

        case DriveForDurationMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: DriveForDurationMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }

            log("Drive: \(msg.seconds) sec, \(msg.reverse ? "backward" : "forward"), speed=\(msg.speed)")

            let speed = msg.reverse ? -abs(msg.speed) : abs(msg.speed)
            HoverboardController.send(.drive(leftThrottle: speed, rightThrottle: speed))
            let initialPos = ARSessionManager.shared.transform.position

            await sleep(seconds: Double(msg.seconds))
            stopRobot()

            let finalPos = ARSessionManager.shared.transform.position
            let result = "Distance traveled: \((finalPos - initialPos).xzProjected.distance)"
            log(result)
            connection.send(LogMessage(text: result))

        case DriveForDistanceMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: DriveForDistanceMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }

            log("Drive: \(msg.meters) m, \(msg.reverse ? "backward" : "forward"), speed=\(msg.speed)")

            let speed = msg.reverse ? -abs(msg.speed) : abs(msg.speed)
            HoverboardController.send(.drive(leftThrottle: speed, rightThrottle: speed))

            // Drive until distance elapsed
            let initialPos = ARSessionManager.shared.transform.position
            repeat {
                _ = try? await ARSessionManager.shared.nextFrame()    // wait one frame
            } while (ARSessionManager.shared.transform.position - initialPos).xzProjected.distance < msg.meters

            stopRobot()

            // Measure actual distance traveled
            let distanceTraveled = "Distance traveled: \((ARSessionManager.shared.transform.position - initialPos).xzProjected.distance) m"
            connection.send(LogMessage(text: distanceTraveled))

        case RotateMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: RotateMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            HoverboardController.send(.rotateInPlaceBy(degrees: msg.degrees))

        case DriveForwardMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: DriveForwardMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            HoverboardController.send(.driveForward(distance: msg.deltaMeters))

        case WatchdogSettingsMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: WatchdogSettingsMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            let configMsg = HoverboardWatchdogMessage(watchdogEnabled: msg.enabled, watchdogSeconds: msg.timeoutSeconds)
            HoverboardController.send(.message(configMsg))

        case PWMSettingsMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: PWMSettingsMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            let configMsg = HoverboardPWMMessage(pwmFrequency: UInt16(msg.pwmFrequency))
            HoverboardController.send(.message(configMsg))

        case ThrottleMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: ThrottleMessage.self) else { break }
            HoverboardController.shared.maxThrottle = msg.maxThrottle

        case PIDGainsMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: PIDGainsMessage.self) else { break }
            let gains = PID.Gains(Kp: msg.Kp, Ki: msg.Ki, Kd: msg.Kd)
            if msg.whichPID == "orientation" {
                HoverboardController.shared.orientationPIDGains = gains
            } else if msg.whichPID == "position" {
                HoverboardController.shared.positionPIDGains = gains
            }

        case HoverboardRTTMeasurementMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: HoverboardRTTMeasurementMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            let responseMsg = await performRTTMeasurements(message: msg)
            connection.send(responseMsg)

        case AngularVelocityMeasurementMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: AngularVelocityMeasurementMessage.self) else { break }
            guard HoverboardController.isConnected else {
                connection.send(LogMessage(text: "Hoverboard not connected!"))
                break
            }
            let responseMsg = await performAngularVelocityMeasurement(steering: msg.steering, for: msg.numSeconds)
            connection.send(responseMsg)

        case PositionGoalToleranceMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: PositionGoalToleranceMessage.self) else { break }
            HoverboardController.shared.positionGoalTolerance = msg.positionGoalTolerance

        case RenderSceneGeometryMessage.id:
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: RenderSceneGeometryMessage.self) else { break }
            ARSessionManager.shared.renderPlanes = msg.planes
            ARSessionManager.shared.renderWorldMeshes = msg.meshes

        case RequestOccupancyMapMessage.id:
            // Send representation of the occupancy map to debug server
            let _ = await NavigationController.shared.updateOccupancy()
            let ourPosition = ARSessionManager.shared.transform.position
            let ourCell = NavigationController.shared.occupancy.positionToCell(ourPosition)
            let responseMsg = OccupancyMapMessage(
                cellsWide: NavigationController.shared.occupancy.cellsWide(),
                cellsDeep: NavigationController.shared.occupancy.cellsDeep(),
                occupancy: NavigationController.shared.getOccupancyArray(),
                robotCell: [ ourCell.cellX, ourCell.cellZ ],
                pathCells: []
            )
            connection.send(responseMsg)

        case DrivePathMessage.id:
            // Debug server has sent us a path back. Assume map dimensions haven't changed.
            guard let msg = JSONMessageDeserializer.decode(receivedMessage, as: DrivePathMessage.self) else { break }
            let path = msg.pathCells.map { (cell: [Int]) -> Vector3 in
                let cell = OccupancyMap.CellIndices(cell[0], cell[1])
                return NavigationController.shared.occupancy.cellToPosition(cell)
            }
            if path.isEmpty {
                // No path, just look around in place
                NavigationController.shared.run(.scan360)
            } else {
                if !msg.pathFinding {
                    NavigationController.shared.run(.follow(path: path))
                } else {
                    // Perform pathfinding between waypoints
                    var computedPath: [Vector3] = []
                    let robotRadius = 0.5 * max(Calibration.robotBounds.x, Calibration.robotBounds.z)
                    var from = ARSessionManager.shared.transform.position
                    for to in path {
                        let pathCells = findPath(NavigationController.shared.occupancy, from, to, robotRadius)
                        let positions = pathCells.map { NavigationController.shared.occupancy.cellToPosition($0) }
                        computedPath += positions
                        from = to
                    }

                    // Send back occupancy map
                    let ourPosition = ARSessionManager.shared.transform.position
                    let ourCell = NavigationController.shared.occupancy.positionToCell(ourPosition)
                    let responseMsg = OccupancyMapMessage(
                        cellsWide: NavigationController.shared.occupancy.cellsWide(),
                        cellsDeep: NavigationController.shared.occupancy.cellsDeep(),
                        occupancy: NavigationController.shared.getOccupancyArray(),
                        robotCell: [ ourCell.cellX, ourCell.cellZ ],
                        pathCells: computedPath.map { (position: Vector3) in
                            let cell = NavigationController.shared.occupancy.positionToCell(position)
                            return [ cell.cellX, cell.cellZ ]
                        }
                    )
                    send(responseMsg)

                    // Traverse
                    NavigationController.shared.run(.follow(path: computedPath))
                }
            }

        case RequestAnnotatedViewMessage.id:
            await getAnnotatedView(connection: connection)

        default:
            log("Error: Unhandled message: \(receivedMessage.id)")
            break
        }
    }

    private func sleep(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func performRTTMeasurements(message msg: HoverboardRTTMeasurementMessage) async -> HoverboardRTTMeasurementMessage {
        // Perform a series of RTT measurements for the server to analyze. We sleep in between
        // successive samples in order to capture a representative variance in RTT.
        let (hoverboardMessages, handle) = HoverboardController.shared.hoverboardMessages.subscribe()
        var rttSeconds: [Double] = []

        for i in 0..<msg.numSamples {
            // Send ping
            let sentAt = Date.timeIntervalSinceReferenceDate
            HoverboardController.shared.send(.message(HoverboardPingMessage(timestamp: sentAt)))

            // Wait for pong
            while true {
                if let data = await hoverboardMessages.first(where: { _ in true}),
                   let pong = HoverboardPongMessage.deserialize(from: data) {
                    let receivedAt = Date.timeIntervalSinceReferenceDate
                    rttSeconds.append(receivedAt - pong.timestamp)
                    break
                }
            }

            // Delay until next test
            if i < (msg.numSamples - 1) {
                await sleep(seconds: msg.delay)
            }
        }

        HoverboardController.shared.hoverboardMessages.unsubscribe(handle)

        // Response to send back to server
        return HoverboardRTTMeasurementMessage(numSamples: msg.numSamples, delay: msg.delay, rttSeconds: rttSeconds)
    }

    private func performAngularVelocityMeasurement(steering: Float, for numSeconds: Double) async -> AngularVelocityMeasurementMessage {
        /*
         * Rotate the hoverboard using the steering input supplied for the amount of seconds
         * specified. Measure the start and end orientation, along with the number of complete
         * revolutions to figure out angular velocity.
         *
         * Algorithm for counting revolutions and total degrees traversed:
         *
         * 1. Start of revolution.
         *      - Save the start vector.
         *      - Proceed to 2.
         * 2. When dot product between current and start vector becomes negative, we have moved
         *    more than 90 degrees and are on the opposite half of the circle.
         *      - Save the vector at this transition as "checkpoint vector".
         *      - Proced to 3.
         * 3. When dot product between current and checkpoint vector becomes negative, we are
         *    now > 90 degrees from checkpoint and > 180 degrees from start vector.
         *      - Proceed to 4.
         * 4. Check for the dot product between current and start to become positive and also that
         *    *from* start vector *to* our current vector is the correct sign.
         *      - If moving clockwise (right), *from* start *to* current should be negative,
         *        indicating we have crossed the starting point.
         *      - If moving counter-clockwise (left), should be positive.
         *      - Record degrees traversed as 360 + (current - start).
         *      - Go back to 1 and start over.
         *
         * When exiting early, the angles traversed are: numRevolution * 360 + degreesPartial,
         * where degreesPartial must be computed as a signed angle and adjusted depending on the
         * direction of rotation to get a value in range [0,360).
         */

        let errorResponse = AngularVelocityMeasurementMessage(steering: steering, numSeconds: numSeconds, angularVelocityResult: 0)

        HoverboardController.send(.rotateInPlace(steering: steering))

        guard var frame = try? await ARSessionManager.shared.nextFrame(),
              sign(steering) != 0 else {
            stopRobot()
            return errorResponse
        }

        let t0 = frame.timestamp
        let deadline = t0 + numSeconds
        var degreesTraversed: Float = 0
        var startVector: Vector3 = frame.camera.transform.forward.xzProjected
        var checkpointVector: Vector3?
        var approachingRevolution = false
        var havePartialResult = false
        log("Step 1")
        repeat {
            havePartialResult = true    // this flag indicates we are mid-way through a revolution, in case we break because of timeout
            let currentVector = frame.camera.transform.forward.xzProjected
            if checkpointVector == nil {
                // Step 2: wait for dot product between current and start to become negative
                if Vector3.dot(startVector, currentVector) < 0 {
                    log("Step 2 -> 3")
                    checkpointVector = currentVector
                }
            } else if !approachingRevolution {
                // Step 3: wait for dot product between current and checkpoint to become negative,
                // indicating we are going to approach start again
                if Vector3.dot(checkpointVector!, currentVector) < 0 {
                    log("Step 3 -> 4")
                    approachingRevolution = true
                }
            } else {    // (approachingRevolution == true)
                // Step 4: check dot product between current and start to be both positive and
                // that from-to rotation of start -> current matches steering sign
                if Vector3.dot(startVector, currentVector) > 0 && sign(steering) == sign(Vector3.signedAngle(from: startVector, to: currentVector, axis: .up)) {
                    // Completed a full revolution, back to step 1
                    log("Step 4 -> 1")
                    degreesTraversed += 360.0 + Vector3.angle(startVector, currentVector)
                    startVector = currentVector
                    checkpointVector = nil
                    approachingRevolution = false
                    havePartialResult = false
                }
            }

            guard let nextFrame = try? await ARSessionManager.shared.nextFrame() else {
                stopRobot()
                return errorResponse
            }
            frame = nextFrame
        } while frame.timestamp <= deadline

        stopRobot()

        if havePartialResult {
            // Need to add how far we have moved from startVector around the circle
            let angle = Vector3.signedAngle(from: startVector, to: frame.camera.transform.forward.xzProjected, axis: .up)
            if sign(angle) == sign(steering) {
                // Indicates < 180 degrees has been traversed, just add the positive angle
                degreesTraversed += abs(angle)
            } else {
                degreesTraversed += 360 - abs(angle)
            }
        }

        let totalSeconds = frame.timestamp - t0
        return AngularVelocityMeasurementMessage(steering: steering, numSeconds: totalSeconds, angularVelocityResult: degreesTraversed / Float(totalSeconds))
    }

    private func renderOccupancyMap(from msg: PeerOccupancyMessage) {
        var occupancy = OccupancyMap(msg.width, msg.depth, msg.cellSide, msg.centerPoint)
        msg.occupancy.withUnsafeBufferPointer { ptr in
            occupancy.updateOccupancyFromArray(ptr.baseAddress, msg.occupancy.count)
        }
        robotOccupancyMapImage = RoBart.renderOccupancyMap(occupancy: occupancy, ourTransform: msg.ourTransform, path: msg.path)
        log("Rendered occupancy map image")
    }

    private func getAnnotatedView(connection: AsyncTCPConnection) async {
        let camera = AnnotatingCamera()
        if let photo = await camera.takePhoto(with: .navigablePoints) {
            connection.send(AnnotatedViewMessage(imageBase64: photo.annotatedJPEGBase64))
        }
    }
}

fileprivate func log(_ message: String) {
    print("[Client] \(message)")
}
