//
//  FollowPerson.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/23/24.
//

import ARKit
import CoreGraphics
import CoreImage
import RealityKit
import Vision
import UIKit

func followPerson(duration followDuration: TimeInterval?, distance followDistance: Float?) async {
    DispatchQueue.main.async {
        ARSessionManager.shared.sceneUnderstanding = false
    }

    var lastPosition: Vector3?
    var lastForward: Vector3?
    
    var nextPersonDetectionTime = Date.now
    var searchForPersonTime: Date? = nil
    var goalPositionHistory: [Vector3] = Array(repeating: ARSessionManager.shared.transform.position, count: 5)
    var historyIdx = 0

    let stopFollowingAt: Date? = followDuration != nil ? Date.now.advanced(by: followDuration!) : nil
    let startedAtPosition = ARSessionManager.shared.transform.position

    while true {
        let now = Date.now
        let currentPosition = ARSessionManager.shared.transform.position.xzProjected
        let currentForward = -ARSessionManager.shared.transform.forward.xzProjected.normalized

        // Time to stop following?
        if let stopFollowingAt = stopFollowingAt,
           now >= stopFollowingAt {
            log("Timeout reached")
            break
        }
        if let distance = followDistance,
           (currentPosition - startedAtPosition).xzProjected.magnitude >= distance {
            log("Distance reached")
            break
        }

        // Detect jumps in the coordinate system and halt if this happens
        if let lastPosition = lastPosition,
           let lastForward = lastForward {
            let displacement = (currentPosition - lastPosition).magnitude
            let degrees = Vector3.angle(lastForward, currentForward)
            if displacement > 1 || degrees >= 45 {
                // No way we moved this much in such a short time, suspect coordinate system glitch
                HoverboardController.shared.send(.drive(leftThrottle: 0, rightThrottle: 0))
            }
        }
        lastPosition = currentPosition
        lastForward = currentForward

        // Perform person detection and update goal position
        if now >= nextPersonDetectionTime,
           let frame = try? await ARSessionManager.shared.nextFrame() {
            let people = detectHumans(in: frame, maximumDistance: Settings.shared.maxPersonDistance)
            
            if let nearestPerson = people.sorted(by: { $0.magnitude > $1.magnitude }).first {
                // Compute goal position safe distance from person
                let targetDistanceToPerson = Settings.shared.followDistance
                let distanceToPerson = (nearestPerson - currentPosition).magnitude
                let direction = (nearestPerson - currentPosition).xzProjected.normalized
                let goalPosition = currentPosition + direction * max(0, distanceToPerson - targetDistanceToPerson)  // keep safe distance
                HoverboardController.shared.send(.driveToFacing(position: goalPosition, forward: direction))

                // Save in circular buffer
                goalPositionHistory[historyIdx] = goalPosition
                historyIdx = (historyIdx + 1) % goalPositionHistory.count

                // We have a goal, so no need to search for person
                searchForPersonTime = nil
            } else {
                // No person! Start a timer to look for the person.
                searchForPersonTime = now.advanced(by: 2)
            }

            nextPersonDetectionTime = now.advanced(by: 1.0 / Settings.shared.personDetectionHz)
        }

        // Search for last person we tracked
        if let searchForPersonAt = searchForPersonTime,
           now >= searchForPersonAt {
            // Compute direction the human appeared to be moving in
            let oldestGoal = goalPositionHistory[circularBufferFirstIndex(buffer: goalPositionHistory, currentIdx: historyIdx)]
            let newestGoal = goalPositionHistory[circularBufferLastIndex(buffer: goalPositionHistory, currentIdx: historyIdx)]
            let directionOfMovement = (newestGoal - oldestGoal).xzProjected.normalized

            // Figure out which direction to turn in and turn 45 degrees toward where they should be
            let angle = Vector3.angle(currentForward, directionOfMovement)
            HoverboardController.shared.send(.rotateInPlaceBy(degrees: Float(angle > 0 ? 45.0 : -45.0)))

            searchForPersonTime = nil
        }

        // Small delay
        try? await Task.sleep(for: .milliseconds(16))
        if Task.isCancelled {
            log("Task cancelled")
            break
        }
    }

    DispatchQueue.main.async {
        ARSessionManager.shared.sceneUnderstanding = true
    }

    log("Finished")
}

fileprivate func circularBufferFirstIndex<T>(buffer: Array<T>, currentIdx: Int) -> Int {
    return (currentIdx + buffer.count - (buffer.count - 1)) % buffer.count
}

fileprivate func circularBufferLastIndex<T>(buffer: Array<T>, currentIdx: Int) -> Int {
    return (currentIdx + buffer.count - 1) % buffer.count
}

fileprivate func log(_ message: String) {
    print("[FollowPerson] \(message)")
}
