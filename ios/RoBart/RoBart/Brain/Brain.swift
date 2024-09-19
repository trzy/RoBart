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
        _speechDetector.$speech.sink { [weak self] (speech: String) in
            guard let self = self,
                  !speech.isEmpty,
                  !isWorking else {
                return
            }
            _task = Task { [weak self] in
                await self?.runTask(humanInput: speech)
            }
        }.store(in: &_subscriptions)
    }

    private func runTask(humanInput: String) async {
        do {
            // Initial human input
            let jpeg = await _camera.takePhoto()
            let messages = [
                MessageParameter.Message(
                    role: .user,
                    content: .list([
                        .text("<HUMAN_INPUT>\(humanInput)</HUMAN_INPUT>"),
                        .image(.init(type: .base64, mediaType: .jpeg, data: jpeg!.base64EncodedString()))
                    ])
                )
            ]
            let params = MessageParameter(model: .claude35Sonnet, messages: messages, maxTokens: _maxTokens, system: .text(Prompts.system))
            let response = try await _claude.createMessage(params)
            if case let .text(responseText) = response.content[0] {
                log("Response: \(responseText)")
            }
        } catch {
            log("Error: \(error)")
        }
        _task = nil
    }

    private func parseBlocks(from text: String) -> [String: String] {
        return [:]
    }
}

fileprivate func log(_ message: String) {
    print("[Brain] \(message)")
}
