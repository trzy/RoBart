//
//  Brain.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//

import Combine
import Foundation
import OpenAI
import SwiftAnthropic

class Brain {
    enum Model: String {
        case claude35Sonnet
        case gpt4o
        case gpt4Turbo
    }

    static let shared = Brain()

    private let _speechDetector = SpeechDetector()
    private var _subscriptions: Set<AnyCancellable> = []

    private let _camera = AnnotatingCamera()

    private let _anthropic = AnthropicServiceFactory.service(apiKey: Settings.shared.anthropicAPIKey, betaHeaders: nil)
    private let _openAI = OpenAI(apiToken: Settings.shared.openAIAPIKey)
    private let _maxTokens = 1024

    private var _task: Task<Void, Never>?

    var isWorking: Bool {
        return _task != nil
    }

    fileprivate init() {
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

    private func runTask(humanInput: String) async {
        _speechDetector.stopListening()
        let timeStarted = Date.now
        var stepNumber = 0

        var history: [ThoughtRepresentable] = []

        // Human speaking to RoBart kicks off the process
        let photo = await _camera.takePhoto()
        let input = HumanInputThought(spokenWords: humanInput, photo: photo)    //TODO: should we move photo into initial observation? "Human spoke. Photo captured."
        history.append(input)

        // Continuously think and act until final response
        var stop = false
        repeat {
            history = prune(history)
            guard let response = await submitToAI(thoughts: history, stopAt: [ObservationsThought.openingTag]) else { break }
            sendDebugLog(modelInput: history, modelOutput: response, timestamp: timeStarted, stepNumber: stepNumber)
            history += response

            for thought in actionableThoughts(in: response) {
                if let intermediateResponse = thought as? IntermediateResponseThought {
                    await speak(intermediateResponse.wordsToSpeak)
                } else if let finalResponse = thought as? FinalResponseThought {
                    await speak(finalResponse.wordsToSpeak)
                    stop = true
                    break
                } else if let actions = thought as? ActionsThought {
                    let observations = await perform(actions, history: history)
                    history.append(observations)
                }
            }

            stepNumber += 1
        } while !stop

        log("Completed task!")
        HoverboardController.shared.send(.drive(leftThrottle: 0, rightThrottle: 0))
        _task = nil
        _speechDetector.startListening()
    }

    private func actionableThoughts(in thoughts: [ThoughtRepresentable]) -> [ThoughtRepresentable] {
        return thoughts.filter { [ IntermediateResponseThought.tag, FinalResponseThought.tag, ActionsThought.tag ].firstIndex(of: $0.tag) != nil }
    }

    private func submitToAI(thoughts: [ThoughtRepresentable], stopAt: [String]) async -> [ThoughtRepresentable]? {
        switch Settings.shared.model {
        case .claude35Sonnet:
            return await submitToClaude(model: .claude35Sonnet, thoughts: thoughts, stopAt: stopAt)

        case .gpt4o:
            return await submitToGPT4(model: .gpt4_o, thoughts: thoughts, stopAt: stopAt)

        case .gpt4Turbo:
            return await submitToGPT4(model: .gpt4_turbo, thoughts: thoughts, stopAt: stopAt)
        }
    }

    private func submitToClaude(model: SwiftAnthropic.Model, thoughts: [ThoughtRepresentable], stopAt: [String]) async -> [ThoughtRepresentable]? {
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
                return responseThoughts.isEmpty ? nil : responseThoughts
            }

            log("Error: No content!")
        } catch {
            log("Error: \(error.localizedDescription)")
        }

        return nil
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
        log("RoBart says: \(wordsToSpeak)")
        guard let mp3Data = await vocalizeWithDeepgram(wordsToSpeak) else { return }
        await AudioManager.shared.playSound(fileData: mp3Data)
    }

    private func perform(_ actionsThought: ActionsThought, history: [ThoughtRepresentable]) async -> ObservationsThought {
        guard let actions = decodeActions(from: actionsThought.json) else {
            return ObservationsThought(text: "The actions generated were not formatted correctly as a JSON array. Try again and use only valid action object types.")
        }

        let maxMoveTime = 6
        let maxTurnTime = 2

        var resultsDescription: [String] = []
        var photos: [AnnotatingCamera.Photo] = []

        let startPosition = ARSessionManager.shared.transform.position
        let startForward = ARSessionManager.shared.transform.forward.xzProjected.normalized

        for action in actions {
            switch action {
            case .move(let move):
                let targetPosition = startPosition + startForward * move.distance
                if NavigationController.shared.occupancy.isLineUnobstructed(startPosition, targetPosition) {
                    resultsDescription.append("Unable to move \(move.distance) meters because there is an obstruction!")
                } else {
                    HoverboardController.shared.send(.driveForward(distance: move.distance))
                    try? await Task.sleep(timeout: .seconds(maxMoveTime), until: { !HoverboardController.shared.isMoving })
                    let endPosition = ARSessionManager.shared.transform.position
                    let actualDistanceMoved = (endPosition - startPosition).magnitude
                    resultsDescription.append("Moved \(actualDistanceMoved) meters \(move.distance >= 0 ? "forwards" : "backwards")")
                }

            case .moveTo(let moveTo):
                guard let navigablePoint = history.findNavigablePoint(moveTo.positionNumber) else {
                    resultsDescription.append("Unable to move to position \(moveTo.positionNumber) because it was not found in any photos")
                    break
                }
                HoverboardController.shared.send(.driveTo(position: navigablePoint.worldPoint))
                try? await Task.sleep(timeout: .seconds(maxMoveTime), until: { !HoverboardController.shared.isMoving })
                let endPosition = ARSessionManager.shared.transform.position
                let actualDistanceMoved = (endPosition - startPosition).magnitude
                resultsDescription.append("Moved \(actualDistanceMoved) meters toward position \(moveTo.positionNumber)")

            case .faceTowardPhoto(let faceTowardPhoto):
                guard let photo = history.findPhoto(named: faceTowardPhoto.photoName) else {
                    resultsDescription.append("Unable to face photo \(faceTowardPhoto.photoName) because it was not found. Only recent observations' photos should be usd.")
                    break
                }

                // In case we have moved to a different position, look to where we would have been
                // looking when photo was taken (a point just ahead of the photo)
                let photoForward = ARSessionManager.shared.direction(fromDegrees: photo.headingDegrees)
                let targetPosition = photo.position + 2 * photoForward
                let targetDirection = (targetPosition - startPosition).xzProjected
                HoverboardController.shared.send(.face(forward: targetDirection))
                try? await Task.sleep(timeout: .seconds(maxTurnTime), until: { !HoverboardController.shared.isMoving })
                let newHeading = ARSessionManager.shared.headingDegrees
                resultsDescription.append("Turned and now facing heading \(newHeading) deg")

            case .faceTowardPoint(let faceTowardPoint):
                guard let navigablePoint = history.findNavigablePoint(faceTowardPoint.positionNumber) else {
                    resultsDescription.append("Unable to face position \(faceTowardPoint.positionNumber) because it was not found in any photos")
                    break
                }
                let targetDirection = (navigablePoint.worldPoint - startPosition).xzProjected
                HoverboardController.shared.send(.face(forward: targetDirection))
                try? await Task.sleep(timeout: .seconds(maxTurnTime), until: { !HoverboardController.shared.isMoving })
                let newHeading = ARSessionManager.shared.headingDegrees
                resultsDescription.append("Turned toward position \(faceTowardPoint.positionNumber) now facing heading \(newHeading) deg")

            case .faceTowardHeading(let faceTowardHeading):
                let targetDirection = ARSessionManager.shared.direction(fromDegrees: faceTowardHeading.headingDegrees)
                HoverboardController.shared.send(.face(forward: targetDirection))
                try? await Task.sleep(timeout: .seconds(maxTurnTime), until: { !HoverboardController.shared.isMoving })
                let newHeading = ARSessionManager.shared.headingDegrees
                resultsDescription.append("Turned and now facing heading \(newHeading) deg")

            case .turnInPlace(let turnInPlace):
                HoverboardController.shared.send(.rotateInPlaceBy(degrees: turnInPlace.degrees))
                try? await Task.sleep(timeout: .seconds(maxTurnTime), until: { !HoverboardController.shared.isMoving })
                let endForward = ARSessionManager.shared.transform.forward.xzProjected
                let actualDegreesTurned = Vector3.angle(startForward, endForward)
                resultsDescription.append("Turned \(actualDegreesTurned) degrees")

            case .takePhoto:
                if let photo = await _camera.takePhoto() {
                    resultsDescription.append("Took photo \(photo.name)")
                    photos.append(photo)
                } else {
                    resultsDescription.append("Camera malfunctioned. No photo.")
                }
            }
        }

        let ourPosition = ARSessionManager.shared.transform.position
        let ourHeading = ARSessionManager.shared.headingDegrees
        let positionStr = String(format: "(%.2f,%.2f)", ourPosition.x, ourPosition.z)
        let headingStr = String(format: "%.f", ourHeading)
        resultsDescription.append("Current coordinate: \(positionStr)")
        resultsDescription.append("Current heading: \(headingStr) deg")

        return ObservationsThought(text: resultsDescription.joined(separator: "\n"), photos: photos)
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
                imageBase64ByName["\(photo.name)"] = photo.jpegBase64
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
