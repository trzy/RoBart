//
//  Brain.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//

import Combine
import Foundation
import SwiftAnthropic

class Brain {
    static let shared = Brain()

    private let _speechDetector = SpeechDetector()
    private var _subscriptions: Set<AnyCancellable> = []

    private let _camera = SmartCamera()

    private let _claude = AnthropicServiceFactory.service(apiKey: Settings.shared.anthropicAPIKey, betaHeaders: nil)
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
        var history: [ThoughtRepresentable] = []
        
        // Human speaking to RoBart kicks off the process
        let photo = await _camera.takePhoto()
        let input = HumanInputThought(spokenWords: humanInput, photo: photo)    //TODO: should we move photo into initial observation? "Human spoke. Photo captured."
        history.append(input)

        // Continuously think and act until final response
        var stop = false
        while !stop {
            guard let response = await submitToClaude(thoughts: history, stopAt: [ObservationsThought.openingTag]) else { break }
            history += response

            for thought in actionableThoughts(in: response) {
                if let intermediateResponse = thought as? IntermediateResponseThought {
                    await speak(intermediateResponse.wordsToSpeak)
                } else if let finalResponse = thought as? FinalResponseThought {
                    await speak(finalResponse.wordsToSpeak)
                    stop = true
                    break
                } else if let actions = thought as? ActionsThought {
                    let observations = await perform(actions)
                    history.append(observations)
                }
            }
        }

        log("Completed task!")
        _task = nil
        _speechDetector.startListening()
    }

    private func actionableThoughts(in thoughts: [ThoughtRepresentable]) -> [ThoughtRepresentable] {
        return thoughts.filter { [ IntermediateResponseThought.tag, FinalResponseThought.tag, ActionsThought.tag ].firstIndex(of: $0.tag) != nil }
    }

    private func submitToClaude(thoughts: [ThoughtRepresentable], stopAt: [String]) async -> [ThoughtRepresentable]? {
        do {
            let response = try await _claude.createMessage(
                MessageParameter(
                    model: .claude35Sonnet,
                    messages: [ thoughts.toClaudeMessage(role: .user) ],
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

    private func speak(_ wordsToSpeak: String) async {
        //TODO
        log("RoBart says: \(wordsToSpeak)")
    }

    private func perform(_ actionsThought: ActionsThought) async -> ObservationsThought {
        guard let actions = decodeActions(from: actionsThought.json) else {
            return ObservationsThought(text: "The actions generated were not formatted correctly as a JSON array. Try again and use only valid action object types.")
        }

        var resultsDescription: [String] = []
        var photos: [SmartCamera.Photo] = []

        for action in actions {
            switch action {
            case .move(let move):
                let startPosition = ARSessionManager.shared.transform.position
                let safeDistance = clamp(move.distance, min: -3.0, max: 3.0)
                //HoverboardController.shared.send(.driveForward(distance: safeDistance))
                //try? await Task.sleep(timeout: .seconds(10), until: { !HoverboardController.shared.isMoving })
                let endPosition = ARSessionManager.shared.transform.position
                let actualDistanceMoved = (endPosition - startPosition).magnitude
                resultsDescription.append("Moved \(actualDistanceMoved) meters \(move.distance >= 0 ? "forwards" : "backwards")")

            case .moveTo(let moveTo):
                resultsDescription.append("Unable to move to position \(moveTo.positionNumber) because this function is not implemented")

            case .turnInPlace(let turnInPlace):
                let startForward = ARSessionManager.shared.transform.forward.xzProjected
                //HoverboardController.shared.send(.rotateInPlaceBy(degrees: turnInPlace.degrees))
                //try? await Task.sleep(timeout: .seconds(10), until: { !HoverboardController.shared.isMoving })
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

        return ObservationsThought(text: resultsDescription.joined(separator: "\n"), photos: photos)
    }
}

fileprivate func log(_ message: String) {
    print("[Brain] \(message)")
}
