//
//  Brain.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
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

import Combine
import Foundation
import OpenAI
import SwiftAnthropic

class Brain: ObservableObject {
    enum Model: String {
        case claude37SonnetLatest
        case claude37Sonnet20250219
        case claude35Sonnet
        case gpt4o
        case gpt4Turbo
    }

    enum DisplayState: String {
        case listening = "👂🏻"
        case thinking = "🧠"
        case acting = "🛞"
        case speaking = "🗣️"
    }

    static let shared = Brain()

    @Published private(set) var displayState: DisplayState? = .listening {
        didSet {
            _video.setDisplayState(displayState)
        }
    }

    private let _speechDetector = SpeechDetector()
    private var _subscriptions: Set<AnyCancellable> = []

    private let _camera = AnnotatingCamera()
    private let _annotationStyle: AnnotatingCamera.Annotation = .navigablePoints

    private let _anthropic = AnthropicServiceFactory.service(apiKey: Settings.shared.anthropicAPIKey, betaHeaders: nil)
    private let _openAI = OpenAI(apiToken: Settings.shared.openAIAPIKey)
    private let _maxTokens = 2048

    private var _task: Task<Void, Never>?
    private var _video = FirstPersonVideo()

    private var _robotRadius: Float {
        return 0.5 * max(Calibration.robotBounds.x, Calibration.robotBounds.z)
    }

    var enabled: Bool = false {
        didSet {
            if enabled && Settings.shared.role == .robot {
                _speechDetector.startListening()
                setDisplayState(to: .listening)
                log("Brain enabled")
            } else {
                _task?.cancel()
                _speechDetector.stopListening()
                setDisplayState(to: nil)
                log("Brain disabled")
            }
        }
    }

    var isWorking: Bool {
        return _task != nil
    }

    private init() {
        // Tasks are kicked off by human speech input
        _speechDetector.$speech.sink { [weak self] (spokenWords: String) in
            guard let self = self,
                  !spokenWords.isEmpty,
                  !isWorking else {
                return
            }
            _task = Task { [weak self] in
                await self?.runTask(humanInput: spokenWords)
            }
        }.store(in: &_subscriptions)
    }

    private func setDisplayState(to state: DisplayState?) {
        DispatchQueue.main.async { [weak self] in
            self?.displayState = state
        }
    }

    private func runTask(humanInput: String) async {
        await _video.record()
        _speechDetector.stopListening()
        let timeStarted = Date.now
        var stepNumber = 0

        var history: [ThoughtRepresentable] = []
        var photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]] = [:]
        var pointsTraversed: [Vector3] = [ ARSessionManager.shared.transform.position ]

        // Human speaking to RoBart kicks off the process
        let photo = await _camera.takePhoto(with: _annotationStyle)
        let input = HumanInputThought(spokenWords: humanInput, photo: photo)    //TODO: should we move photo into initial observation? "Human spoke. Photo captured."
        history.append(input)

        // Continuously think and act until final response
        var stop = false
        repeat {
            history = prune(history)
            guard let response = await submitToAI(thoughts: history, stopAt: [ObservationsThought.openingTag]) else { break }
            sendDebugLog(modelInput: history, modelOutput: response, timestamp: timeStarted, stepNumber: stepNumber)
            history += response

            if Task.isCancelled {
                log("Task cancelled!")
                break
            }

            for thought in actionableThoughts(in: response) {
                if let intermediateResponse = thought as? IntermediateResponseThought {
                    await speak(intermediateResponse.wordsToSpeak)
                } else if let finalResponse = thought as? FinalResponseThought {
                    await speak(finalResponse.wordsToSpeak)
                    stop = true
                    break
                } else if let actions = thought as? ActionsThought {
                    let observations = await perform(actions, history: history, photosByNavigablePoint: &photosByNavigablePoint, pointsTraversed: &pointsTraversed)
                    history.append(observations)
                }
            }

            stepNumber += 1
        } while !stop

        log("Completed task!")
        HoverboardController.shared.send(.drive(leftThrottle: 0, rightThrottle: 0))
        _task = nil
        if enabled {
            _speechDetector.startListening()
            setDisplayState(to: .listening)
        } else {
            setDisplayState(to: nil)
        }
        await _video.finish()
    }

    private func actionableThoughts(in thoughts: [ThoughtRepresentable]) -> [ThoughtRepresentable] {
        return thoughts.filter { [ IntermediateResponseThought.tag, FinalResponseThought.tag, ActionsThought.tag ].firstIndex(of: $0.tag) != nil }
    }

    private func submitToAI(thoughts: [ThoughtRepresentable], stopAt: [String]) async -> [ThoughtRepresentable]? {
        setDisplayState(to: .thinking)

        switch Settings.shared.model {
        case .claude37SonnetLatest:
            return await submitToClaude(model: .other("claude-3-7-sonnet-latest"), thoughts: thoughts, stopAt: stopAt)

        case .claude37Sonnet20250219:
            return await submitToClaude(model: .other("claude-3-7-sonnet-20250219"), thoughts: thoughts, stopAt: stopAt)

        case .claude35Sonnet:
            return await submitToClaude(model: .claude35Sonnet, thoughts: thoughts, stopAt: stopAt)

        case .gpt4o:
            return await submitToGPT4(model: .gpt4_o, thoughts: thoughts, stopAt: stopAt)

        case .gpt4Turbo:
            return await submitToGPT4(model: .gpt4_turbo, thoughts: thoughts, stopAt: stopAt)
        }
    }

    private func submitToClaude(model: SwiftAnthropic.Model, thoughts: [ThoughtRepresentable], stopAt: [String]) async -> [ThoughtRepresentable] {
        do {
            let response = try await _anthropic.createMessage(
                MessageParameter(
                    model: model,
                    messages: [ thoughts.toAnthropicMessage(role: .user) ],
                    maxTokens: _maxTokens,
                    system: .text(Prompts.system),
                    stopSequences: stopAt.isEmpty ? nil : stopAt
                )
            )

            if case let .text(responseText) = response.content[0] {
                log("Response: \(responseText)")
                let responseThoughts = parseBlocks(from: responseText).toThoughts()
                if responseThoughts.isEmpty {
                    // This occasionally happens when there is an error or Claude thinks the
                    // content is prohibited. We deliver its response verbatim.
                    return [ FinalResponseThought(spokenWords: responseText) ]
                }
                return responseThoughts
            }

            log("Error: No content!")
            return [ FinalResponseThought(spokenWords: "An error occurred and Claude delivered no content in its response.") ]
        } catch {
            log("Error: \(error.localizedDescription)")
            return [ FinalResponseThought(spokenWords: "The following error occurred: \(error.localizedDescription)")]
        }
    }

    private func submitToGPT4(model: String, thoughts: [ThoughtRepresentable], stopAt: [String]) async -> [ThoughtRepresentable]? {
        do {
            log("Messages: \(thoughts.toOpenAIUserMessages())")
            let query = ChatQuery(
                messages: [ .system(.init(content: Prompts.system)) ] + thoughts.toOpenAIUserMessages(),
                model: model,
                stop: stopAt.isEmpty ? nil : .stringList(stopAt)
            )
            let response = try await _openAI.chats(query: query)

            if let responseText = response.choices[0].message.content?.string {
                log("Response: \(responseText)")
                let responseThoughts = parseBlocks(from: responseText).toThoughts()
                return responseThoughts.isEmpty ? nil : responseThoughts
            }
        } catch {
            log("Error: \(error.localizedDescription)")
        }

        return nil
    }

    private func prune(_ history: [ThoughtRepresentable]) -> [ThoughtRepresentable] {
        let numActionsToKeep = 2                // how many of the last actions objects to keep
        let numObservationsToKeep = 5           // ... observations
        let numPlansToKeep = 2                  // ... plans
        let numMemoriesToKeep = 1               // ... memories
        let numIntermediateResponsesToKeep = 0  // ... intermediate responses
        let numThoughtsWithPhotosToKeep = 1     // how many thoughts with photos to keep (only photos are dropped, not thoughts)

        var prunedHistory = history

        // Remove photos from old thoughts
        var encountered = 0
        for i in (0..<prunedHistory.count).reversed() {
            if !prunedHistory[i].photos.isEmpty {
                encountered += 1
                if encountered > numThoughtsWithPhotosToKeep {
                    prunedHistory[i] = prunedHistory[i].withPhotosRemoved()
                }
            }
        }

        // Remove old thoughts by type
        prunedHistory = keepLastN(of: ActionsThought.self, in: prunedHistory, n: numActionsToKeep)
        prunedHistory = keepLastN(of: ObservationsThought.self, in: prunedHistory, n: numObservationsToKeep)
        prunedHistory = keepLastN(of: PlanThought.self, in: prunedHistory, n: numPlansToKeep)
        prunedHistory = keepLastN(of: MemoryThought.self, in: prunedHistory, n: numMemoriesToKeep)
        prunedHistory = keepLastN(of: IntermediateResponseThought.self, in: prunedHistory, n: numIntermediateResponsesToKeep)

        return prunedHistory
    }

    private func keepLastN<T: ThoughtRepresentable>(of type: T.Type, in history: [ThoughtRepresentable], n: Int) -> [ThoughtRepresentable] {
        // Find all indices that have a thought of the given type
        var indicesWithDesiredType: [Int] = []
        for (idx, thought) in history.enumerated() {
            if thought is T {
                indicesWithDesiredType.append(idx)
            }
        }

        // Preserve the last n (i.e., drop the last n from the kill list)
        let indicesToRemove = indicesWithDesiredType.dropLast(n)
        return history.enumerated().compactMap { idx, thought in indicesToRemove.contains(idx) ? nil : thought }
    }

    private func speak(_ wordsToSpeak: String) async {
        setDisplayState(to: .speaking)
        log("RoBart says: \(wordsToSpeak)")
        guard let mp3Data = await vocalizeWithDeepgram(wordsToSpeak) else { return }
        await _video.addMP3AudioClip(mp3Data)
        await AudioManager.shared.playSound(fileData: mp3Data)
    }

    private func perform(_ actionsThought: ActionsThought, history: [ThoughtRepresentable], photosByNavigablePoint: inout [Int: [AnnotatingCamera.Photo]], pointsTraversed: inout [Vector3]) async -> ObservationsThought {
        setDisplayState(to: .acting)

        guard let actions = decodeActions(from: actionsThought.json) else {
            return ObservationsThought(text: "The actions generated were not formatted correctly as a JSON array. Try again and use only valid action object types.")
        }

        let maxTurnTime = 2
        let maxMoveTime = 6

        var resultsDescription: [String] = []
        var photosThisStep: [AnnotatingCamera.Photo] = []

        let startPosition = ARSessionManager.shared.transform.position
        let startForward = -ARSessionManager.shared.transform.forward.xzProjected.normalized

        for action in actions {
            _ = await NavigationController.shared.updateOccupancy()

            switch action {
            case .move(let move):
                let targetPosition = startPosition + startForward * move.distance
                if !NavigationController.shared.occupancy.isLineUnobstructed(startPosition, targetPosition) {
                    resultsDescription.append("Unable to move \(move.distance) meters because there is an obstruction!")
                } else {
                    _video.setPath([ startPosition, targetPosition ])
                    HoverboardController.shared.send(.driveForward(distance: move.distance))
                    try? await Task.sleep(timeout: .seconds(maxMoveTime), until: { !HoverboardController.shared.isMoving })
                    let endPosition = ARSessionManager.shared.transform.position
                    let actualDistanceMoved = (endPosition - startPosition).magnitude
                    resultsDescription.append("Moved \(actualDistanceMoved) meters \(move.distance >= 0 ? "forwards" : "backwards")")
                    _video.clearPath()
                }

            case .moveTo(let moveTo):
                let resultDescription = await moveToPoint(moveTo, photosByNavigablePoint: photosByNavigablePoint, maxTurnTime: Double(maxTurnTime), maxMoveTime: Double(maxMoveTime))
                resultsDescription.append(resultDescription)

            case .faceToward(let faceToward):
                guard let navigablePoint = history.findNavigablePoint(pointID: faceToward.pointNumber) else {
                    resultsDescription.append("Unable to face point \(faceToward.pointNumber) because it was not found in any photos")
                    break
                }
                let targetDirection = (navigablePoint.worldPoint - startPosition).xzProjected
                let succeeded = await face(forward: targetDirection)
                guard succeeded else {
                    resultsDescription.append("Unable to face point \(faceToward.pointNumber). Hit an obstruction!")
                    break
                }
                let newHeading = ARSessionManager.shared.headingDegrees
                resultsDescription.append("Turned toward point \(faceToward.pointNumber) now facing heading \(newHeading) deg")

            case .faceTowardHeading(let faceTowardHeading):
                let targetDirection = ARSessionManager.shared.direction(fromDegrees: faceTowardHeading.headingDegrees)
                let succeeded = await face(forward: targetDirection)
                guard succeeded else {
                    resultsDescription.append("Unable to face heading \(faceTowardHeading.headingDegrees) deg. Hit an obstruction!")
                    break
                }
                let newHeading = ARSessionManager.shared.headingDegrees
                resultsDescription.append("Turned and now facing heading \(newHeading) deg")

            case .turnInPlace(let turnInPlace):
                guard let actualDegreesTurned = await turn(degrees: turnInPlace.degrees) else {
                    resultsDescription.append("Unable to turn \(turnInPlace.degrees) degrees. Hit an obstruction!")
                    break
                }
                resultsDescription.append("Turned \(actualDegreesTurned) degrees")

            case .scan360:
                let scanPhotos = await scan360AndTakePhotos()
                photosThisStep += scanPhotos
                resultsDescription.append("Completed scan")

            case .takePhoto:
                if let photo = await _camera.takePhoto(with: _annotationStyle) {
                    resultsDescription.append("Took photo \(photo.name)")
                    photosThisStep.append(photo)
                } else {
                    resultsDescription.append("Camera malfunctioned. No photo.")
                }

            case .backOut:
                let successful = await backOutManeuver(pointsTraversed: &pointsTraversed)
                if successful {
                    resultsDescription.append("Back out manuever succeeded")
                } else {
                    resultsDescription.append("Back out maneuver failed")
                }

            case .followHuman(let followHuman):
                log("Following...")
                await followPerson(duration: followHuman.seconds, distance: followHuman.distance)
                resultsDescription.append("Finished following human")
            }

            // Stop moving
            HoverboardController.shared.send(.drive(leftThrottle: 0, rightThrottle: 0))

            // Record point reached
            pointsTraversed.append(ARSessionManager.shared.transform.position)

            // Update video recording data
            _video.setNavigablePoints(photosByNavigablePoint)
        }

        // Log current position and heading to observations
        let ourPosition = ARSessionManager.shared.transform.position
        let ourForward = -ARSessionManager.shared.transform.forward.xzProjected.normalized
        let ourHeading = ARSessionManager.shared.headingDegrees
        let positionStr = String(format: "(x=%.2f meters,y=%.2f meters)", ourPosition.x, ourPosition.z)
        let headingStr = String(format: "%.f", ourHeading)
        resultsDescription.append("Current position: \(positionStr)")
        resultsDescription.append("Current heading: \(headingStr) deg")

        // Caption photos taken this cycle
        var captionedPhotos: [(photo: AnnotatingCamera.Photo, caption: String)] = []
        for i in 0..<photosThisStep.count {
            let photo = photosThisStep[i]
            var caption: [String] = []
            if let photoForward = photo.forward?.xzProjected.normalized,
               Vector3.angle(ourForward, photoForward) < 20 {
                caption.append("Current view")
            } else if i == photosThisStep.count - 1 {
                caption.append("Most recent photo")
            }
            caption.append("\(photo.name) taken during last actions step")
            captionedPhotos.append((photo: photo, caption: caption.joined(separator: ", ")))
        }

        // Attach older photos that have navigable points
        if _annotationStyle == .navigablePoints {
            let photos = producePhotosWithReachablePoints(from: photosByNavigablePoint)
// Commenting out because Claude seems to complain more about copyright when we use more images.
// Instead, we regurgitate descriptions of the waypoints from memory.
//            for i in 0..<photos.count {
//                captionedPhotos.append((photo: photos[i], caption: "\(photos[i].name) taken during a previous step but with reachable navigable points"))
//            }
            if let memoryThought = history.reversed().first(where: { $0 is MemoryThought }) as? MemoryThought,
               let memories = decodeMemories(from: memoryThought.json) {

                let occupancy = NavigationController.shared.occupancy
                let reachableLandmarks = memories.filter { (memory: Memory) in
                    // Reachable by direct line or path
                    guard let point = findNavigablePoint(pointID: memory.pointNumber, in: photosByNavigablePoint) else { return false }
                    return occupancy.isLineUnobstructed(ourPosition, point.worldPoint) || findPath(occupancy, ourPosition, point.worldPoint, _robotRadius).size() > 0
                }
                if !reachableLandmarks.isEmpty {
                    resultsDescription.append("The following previously-observed navigable points can still be reached:")
                    for landmark in reachableLandmarks {
                        resultsDescription.append("  \(landmark.pointNumber): \(landmark.description)")
                    }
                }
            }
        }

        // Update databases of photos and navigable points with new photos
        updateNavigablePointDatabase(database: &photosByNavigablePoint, with: photosThisStep)

        // Obtain navigable points referenced in memory
        let memorizedPoints = getLandmarkPointsFromLastMemory(history: history, photosByNavigablePoint: photosByNavigablePoint)

        // Render image with memorized points as landmarks and add it to observations
        if let mapImage = renderMap(
            occupancy: NavigationController.shared.occupancy,
            ourTransform: ARSessionManager.shared.transform,
            navigablePoints: memorizedPoints,
            pointsTraversed: pointsTraversed
        ) {
//            if let image = AnnotatingCamera.Photo.createWithoutAnnotations(name: "Current map", originalImage: mapImage) {
//                captionedPhotos.append((photo: image, caption: "Current map"))
//            }
        }

        // Describe which points are currenrtly accessible so RoBart doesn't hallucinate or refer
        // to an old point no longer within view
        if _annotationStyle == .navigablePoints {
            let allowablePointIDs = Set(captionedPhotos.flatMap({ $0.photo.navigablePoints }).map({ "\($0.id)" }))
            if allowablePointIDs.isEmpty {
                resultsDescription.append("No navigable points are reachable. Area may be obstructed or RoBart may be stuck. Proceed carefully.")
            }
            // Redundant? LLM should be able to understand from images what points are accessible.
//            else {
//                resultsDescription.append("Currently accessible navigable points: \(allowablePointIDs.joined(separator: ", "))")
//            }
        }

        return ObservationsThought(text: resultsDescription.joined(separator: "\n"), captionedPhotos: captionedPhotos)
    }

    private func moveToPoint(_ moveTo: MoveToAction, photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]], maxTurnTime: Double, maxMoveTime: Double) async -> String {
        guard let navigablePoint = findNavigablePoint(pointID: moveTo.pointNumber, in: photosByNavigablePoint) else {
            return "Unable to move to point \(moveTo.pointNumber) because it was not found in any photos"
        }

        let startPosition = ARSessionManager.shared.transform.position
        let expectedMovementDistance = (navigablePoint.worldPoint - startPosition).magnitude

        if NavigationController.shared.occupancy.isLineUnobstructed(startPosition, navigablePoint.worldPoint) {
            // There is an unobstructed straight line path

            // Orient toward goal initially
            let direction = (navigablePoint.worldPoint - startPosition).xzProjected.normalized
            HoverboardController.shared.send(.face(forward: direction))
            try? await Task.sleep(timeout: .seconds(maxTurnTime), until: { !HoverboardController.shared.isMoving })

            // We will approach to within a short distance, but not actually onto the point,
            // because the robot likes to pick points that are very close to furniture it wants
            // to inspect
            let distanceToPoint = (navigablePoint.worldPoint - startPosition).magnitude
            let distanceToMove = max(0.5, distanceToPoint - 0.5)
            let goalPosition = startPosition + distanceToMove * direction
            _video.setPath([ startPosition, goalPosition ])

            // Move to goal
            HoverboardController.shared.send(.driveTo(position: goalPosition))
            try? await Task.sleep(timeout: .seconds(maxMoveTime), until: { !HoverboardController.shared.isMoving })
        } else {
            // Attempt to pathfind
            let pathCells = findPath(NavigationController.shared.occupancy, startPosition, navigablePoint.worldPoint, _robotRadius)
            let path = pathCells.map { NavigationController.shared.occupancy.cellToPosition($0) }
            if path.isEmpty {
                return "Unable to move to point \(moveTo.pointNumber) because there is no clear path to it"
            }
            _video.setPath(path)

            // Move along path
            NavigationController.shared.run(.follow(path: path))
            try? await Task.sleep(timeout: .seconds(maxMoveTime * Double(path.count) / 2), until: { !HoverboardController.shared.isMoving})
        }

        _video.clearPath()

        let endPosition = ARSessionManager.shared.transform.position
        let actualDistanceMoved = (endPosition - startPosition).magnitude
        let pctOfExpected = 100 * (actualDistanceMoved / expectedMovementDistance)

        if pctOfExpected < 0.25 {
            return "Moved \(pctOfExpected)% of the way to the intended goal: \(actualDistanceMoved) meters toward point \(moveTo.pointNumber) -- much less than expected; RoBart seems to be obstructed or stuck!"
        }
        else if pctOfExpected < 0.8 {
            return "Moved \(pctOfExpected)% of the way to the intended goal: \(actualDistanceMoved) meters toward point \(moveTo.pointNumber) -- this seems a bit short, maybe there was an obstruction"
        } else {
            return "Moved \(pctOfExpected)% of the way to the intended goal: \(actualDistanceMoved) meters toward point \(moveTo.pointNumber)"
        }
    }

    private func scan360AndTakePhotos() async -> [AnnotatingCamera.Photo] {
        // Divide the circle into 45 degree arcs, ending on our start orientation
        let startingForward = -ARSessionManager.shared.transform.forward
        var steps: [Vector3] = []
        for i in 1...7 {
            steps.append(startingForward.rotated(by: Float(45 * i), about: .up))
        }
        steps.append(startingForward)   // return to initial position

        // Move between them
        var photos: [AnnotatingCamera.Photo] = []
        var wasSuccessful = true
        var numPointsSucceeded =  0
        for targetForward in steps {
            let succeeded = await face(forward: targetForward)
            guard succeeded else {
                wasSuccessful = false
                break
            }
            if let photo = await _camera.takePhoto(with: _annotationStyle) {
                photos.append(photo)
            }
            numPointsSucceeded += 1
        }

        // If not successful, return to start and try from the other side
        if !wasSuccessful {
            _ = await face(forward: startingForward)

            // Reverse the array and drop the number of points we visited on the other side
            let reversedSteps = steps.reversed().dropLast(numPointsSucceeded)
            for targetForward in reversedSteps {
                let succeeded = await face(forward: targetForward)
                guard succeeded else {
                    break
                }
                if let photo = await _camera.takePhoto(with: _annotationStyle) {
                    photos.append(photo)
                }
            }
        }

        return photos
    }

    private func turn(degrees: Float) async -> Float? {
        let prevForward = -ARSessionManager.shared.transform.forward.xzProjected
        let targetForward = prevForward.rotated(by: degrees, about: .up)
        let succeeded = await face(forward: targetForward)
        guard succeeded else {
            return nil
        }
        let currentForward = -ARSessionManager.shared.transform.forward.xzProjected
        let degreesActuallyTurned = Vector3.signedAngle(from: prevForward, to: currentForward, axis: .up)
        return degreesActuallyTurned
    }

    private func face(forward targetForward: Vector3) async -> Bool {
        let prevForward = -ARSessionManager.shared.transform.forward.xzProjected
        let desiredDegrees = Vector3.angle(prevForward, targetForward)
        let waitDuration = Double(Float.lerp(from: 2, to: 4, t: desiredDegrees / 180))
        HoverboardController.shared.send(.face(forward: targetForward))
        try? await Task.sleep(timeout: .seconds(waitDuration), until: { !HoverboardController.shared.isMoving })
        let finished = !HoverboardController.shared.isMoving   // reached target rather than timed out
        let currentForward = -ARSessionManager.shared.transform.forward.xzProjected
        let actualDegrees = Vector3.angle(prevForward, currentForward)
        let pctError = abs((actualDegrees / desiredDegrees) - 1.0)  // tolerate some inaccuracy because when PID shuts off, we may have momentum that creates a bigger error
        if !finished && pctError > 0.2 {
            // Failed to turn, return to original position
            log("Aborted turn. Desired degrees=\(desiredDegrees), actual=\(actualDegrees), pctError=\(pctError)")
            HoverboardController.shared.send(.face(forward: prevForward))
            try? await Task.sleep(timeout: .seconds(waitDuration), until: { !HoverboardController.shared.isMoving })
            return false
        }
        return true
    }

    private func backOutManeuver(pointsTraversed: inout [Vector3]) async -> Bool {
        // Moving backwards, find some point at least one cell away
        let startPosition = ARSessionManager.shared.transform.position
        var endIdx = -1
        for i in stride(from: pointsTraversed.count - 1, to: -1, by: -1) {
            if (startPosition - pointsTraversed[i]).magnitude >= NavigationController.cellSide {
                endIdx = i
                break
            }
        }

        if endIdx <= 0 {
            // Nowhere to move, failed
            return false
        }

        // Attempt to follow path facing *backwards* to minimize turning
        for i in stride(from: pointsTraversed.count - 1, to: endIdx - 1, by: -1) {
            // Face away from waypoint
            let awayFromWaypoint = (ARSessionManager.shared.transform.position - pointsTraversed[i]).xzProjected
            HoverboardController.shared.send(.face(forward: awayFromWaypoint))
            try? await Task.sleep(timeout: .seconds(2), while: { HoverboardController.shared.isMoving })

            // Move backwards to waypoint
            HoverboardController.shared.send(.driveToFacing(position: pointsTraversed[i], forward: awayFromWaypoint))
            try? await Task.sleep(timeout: .seconds(10), while: { HoverboardController.shared.isMoving })
        }

        // Consider it a success if we moved at least half the net distance to the goal
        let desiredDistance = (startPosition - pointsTraversed[endIdx]).xzProjected.magnitude
        let actualDistance = (startPosition - ARSessionManager.shared.transform.position).xzProjected.magnitude
        if actualDistance >= (0.5 * desiredDistance) {
            // May be unstuck, remove the indices we traversed back along
            pointsTraversed.removeLast(pointsTraversed.count - endIdx)
            return true
        }
        return false
    }

    private func producePhotosWithReachablePoints(from photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]]) -> [AnnotatingCamera.Photo] {
        // For all the photos currently in the database, determine which of their navigable points,
        // if any, are reachable and produce new photos annotated only with those points
        let ourPosition = ARSessionManager.shared.transform.position

        // Deduplicate the same photos by looking at name
        var photosByName: [String: AnnotatingCamera.Photo] = [:]
        for photo in photosByNavigablePoint.values.flatMap({ $0 }) {
            photosByName[photo.name] = photo
        }
        let photos = photosByName.values

       // Produce updated photos if there are any reachable navigable points
        var updatedPhotos: [AnnotatingCamera.Photo] = []
        let occupancy = NavigationController.shared.occupancy
        for photo in photos {
            let reachableNavigablePoints = photo.navigablePoints.filter {
                // Reachable by direct line or path
                return occupancy.isLineUnobstructed(ourPosition, $0.worldPoint) || findPath(occupancy, ourPosition, $0.worldPoint, _robotRadius).size() > 0
            }
            if reachableNavigablePoints.isEmpty {
                continue
            }
            if let updatedPhoto = AnnotatingCamera.Photo.createWithNavigablePointAnnotations(
                name: photo.name,
                originalImage: photo.originalImage,
                navigablePoints: reachableNavigablePoints,
                worldToCamera: photo.worldToCamera,
                intrinsics: photo.intrinsics,
                position: photo.position,
                forward: photo.forward,
                headingDegrees: photo.headingDegrees
            ) {
                updatedPhotos.append(updatedPhoto)
            }
        }
        return updatedPhotos
    }

    private func updateNavigablePointDatabase(database photosByNavigablePoint: inout [Int: [AnnotatingCamera.Photo]], with photos: [AnnotatingCamera.Photo]) {
        for photo in photos {
            for point in photo.navigablePoints {
                var photosContainingPoint = photosByNavigablePoint[point.id] ?? []
                photosContainingPoint.append(photo)
                photosByNavigablePoint[point.id] = photosContainingPoint
            }
        }
    }

    private func findNavigablePoint(pointID: Int, in photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]]) -> AnnotatingCamera.NavigablePoint? {
        return photosByNavigablePoint[pointID]?.first?.findNavigablePoint(id: pointID)
    }

    // These points are not necessarily reachable but were memorized as landmarks
    private func getLandmarkPointsFromLastMemory(history: [ThoughtRepresentable], photosByNavigablePoint: [Int: [AnnotatingCamera.Photo]]) -> [AnnotatingCamera.NavigablePoint] {
        guard let memoryThought = history.reversed().first(where: { $0 is MemoryThought }) as? MemoryThought,
              let memories = decodeMemories(from: memoryThought.json) else { return [] }

        // Navigable points can appear in multiple photos, so just use first photo associated with any given point
        return memories.compactMap { photosByNavigablePoint[$0.pointNumber]?.first?.findNavigablePoint(id: $0.pointNumber) }
    }

    private func sendDebugLog(modelInput: [ThoughtRepresentable], modelOutput: [ThoughtRepresentable], timestamp: Date, stepNumber: Int) {
        // Timestamp string will be used to create directories on server
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestampString = dateFormatter.string(from: timestamp)

        // Get all photos
        var imageBase64ByName: [String: String] = [:]
        for thought in modelInput {
            for photo in thought.photos {
                imageBase64ByName["\(photo.name)"] = photo.annotatedJPEGBase64
            }
        }

        // Send message to server
        let msg = AIStepMessage(
            timestamp: timestampString,
            stepNumber: stepNumber,
            modelInput: modelInput.toHumanReadableContent(),
            modelOutput: modelOutput.toHumanReadableContent(),
            imagesBase64: imageBase64ByName
        )
        Client.shared.send(msg)
    }
}

fileprivate func log(_ message: String) {
    print("[Brain] \(message)")
}
