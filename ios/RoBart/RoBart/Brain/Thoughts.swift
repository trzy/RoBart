//
//  Thoughts.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/18/24.
//
//  We use a multimodal ReAct-like prompting strategy, consisting of various different blocks of
//  content representing different stages of "thought". These are represented in a structured form
//  before being converted to the format the AI's API expects.
//

import OpenAI
import SwiftAnthropic

protocol ThoughtRepresentable {
    static var tag: String { get }
    var photos: [SmartCamera.Photo] { get }
    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject]
    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content]
    func withPhotosRemoved() -> ThoughtRepresentable
}

extension ThoughtRepresentable {
    var tag: String { Self.tag }
    var photos: [SmartCamera.Photo] { [] }
    func withPhotosRemoved() -> ThoughtRepresentable {
        return self
    }

    static var openingTag: String { "<\(Self.tag)>" }
    static var closingTag: String { "</\(Self.tag)>" }

    fileprivate var openingTag: String { Self.openingTag }
    fileprivate var closingTag: String { Self.closingTag }
}

extension Array where Element == ThoughtRepresentable {
    /// Converts an array of `ThoughtRepresentable` objects to a single `Message` object with the
    /// given role, for use with Claude.
    /// - Parameter role: Message role.
    /// - Returns: A `Message` object for use with Claude via SwiftAnthropic.
    func toAnthropicMessage(role: MessageParameter.Message.Role) -> MessageParameter.Message {
        return MessageParameter.Message(role: role, content: .list(self.toAnthropicContentObjects()))
    }

    /// Converts an array of `ThoughtRepresentable` objects into an array of `ContentObject`, for
    /// use with Claude.
    /// - Returns: Array of `ContentObject` objects for use with Claude via SwiftAnthropic.
    fileprivate func toAnthropicContentObjects() -> [MessageParameter.Message.Content.ContentObject] {
        return self.flatMap { $0.anthropicContent() }
    }

    /// Converts an array of `ThoughtRepresentable` objects to a list of `ChatCompletionUserMessageParam`
    /// objects (user message content), for use with GPT-4.
    /// - Returns: Array of `ChatCompletionUserMessageParam`.
    func toOpenAIUserMessages() -> [ChatQuery.ChatCompletionMessageParam] {
        let content = self.flatMap { $0.openAIContent() }
        return content.map { ChatQuery.ChatCompletionMessageParam.user(.init(content: $0)) }
    }

    func findNavigablePoint(_ pointID: Int) -> SmartCamera.NavigablePoint? {
        // Search all photos in all thoughts (in reverse order because it is more likely that a
        // recent photo will contain the desired point)
        for thought in self.reversed() {
            for photo in thought.photos {
                for navigablePoint in photo.navigablePoints {
                    if navigablePoint.id == pointID {
                        return navigablePoint
                    }
                }
            }
        }
        return nil
    }
}

extension Array where Element == (tag: String, contents: String) {
    /// Converts parsed AI response into `ThoughtRepresentable` objects.
    /// - Returns: Array of `ThoughtRepresentable` objects representing the parsed input text.
    func toThoughts() -> [ThoughtRepresentable] {
        return self.compactMap { (block: (tag: String, contents: String)) in
            if block.tag == HumanInputThought.tag {
                return HumanInputThought(spokenWords: block.contents, photo: nil)
            } else if block.tag == ObservationsThought.tag {
                return ObservationsThought(text: block.contents)
            } else if block.tag == PlanThought.tag {
                return PlanThought(plan: block.contents)
            } else if block.tag == ActionsThought.tag {
                return ActionsThought(json: block.contents)
            } else if block.tag == IntermediateResponseThought.tag {
                return IntermediateResponseThought(spokenWords: block.contents)
            } else if block.tag == FinalResponseThought.tag {
                return FinalResponseThought(spokenWords: block.contents)
            } else {
                return nil
            }
        }
    }
}

struct HumanInputThought: ThoughtRepresentable {
    private let _spokenWords: String
    private let _photo: SmartCamera.Photo?

    static var tag: String { "HUMAN_INPUT" }

    var photos: [SmartCamera.Photo] {
        if let photo = _photo {
            return [photo]
        }
        return []
    }

    init(spokenWords: String, photo: SmartCamera.Photo?) {
        _spokenWords = spokenWords
        _photo = photo
    }

    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject] {
        var content: [MessageParameter.Message.Content.ContentObject] = [ .text("\(openingTag)\(_spokenWords)") ]
        if let photo = _photo {
            content.append(.text("\n\(photo.name):"))
            content.append(.image(.init(type: .base64, mediaType: .jpeg, data: photo.jpegBase64)))
        }
        content.append(.text(closingTag))
        return content
    }

    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] {
        var content: [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] = [ .string("\(openingTag)\(_spokenWords)") ]
        if let photo = _photo {
            let visionContent = ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content.vision([
                .chatCompletionContentPartTextParam(.init(text: "\(photo.name)")),
                .chatCompletionContentPartImageParam(.init(imageUrl: .init(url: "data:image/jpeg;base64,\(photo.jpegBase64)", detail: .auto)))
            ])
            content.append(visionContent)
        }
        content.append(.string(closingTag))
        return content
    }
}

struct ObservationsThought: ThoughtRepresentable {
    private let _text: String?
    private let _photos: [SmartCamera.Photo]

    static var tag: String { "OBSERVATIONS" }

    var photos: [SmartCamera.Photo] { _photos }

    init(photos: [SmartCamera.Photo]) {
        _text = nil
        _photos = photos
    }

    init(text: String) {
        _text = text
        _photos = []
    }

    init(text: String, photos: [SmartCamera.Photo]) {
        _text = text
        _photos = photos
    }

    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject] {
        var content: [MessageParameter.Message.Content.ContentObject] = [ .text(openingTag) ]
        if let text = _text {
            content.append(.text(text))
        }
        for photo in _photos {
            content.append(.text("\n\(photo.name):"))
            content.append(.image(.init(type: .base64, mediaType: .jpeg, data: photo.jpegBase64)))
        }
        content.append(.text(closingTag))
        return content
    }

    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] {
        var content: [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] = [ .string(openingTag) ]
        if let text = _text {
            content.append(.string(text))
        }
        for photo in _photos {
            let visionContent = ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content.vision([
                .chatCompletionContentPartTextParam(.init(text: "\n\(photo.name)")),
                .chatCompletionContentPartImageParam(.init(imageUrl: .init(url: "data:image/jpeg;base64,\(photo.jpegBase64)", detail: .auto)))
            ])
            content.append(visionContent)
        }
        content.append(.string(closingTag))
        return content
    }

    func withPhotosRemoved() -> ThoughtRepresentable {
        if let text = _text {
            return ObservationsThought(text: text)
        } else {
            return ObservationsThought(photos: [])
        }
    }
}

struct PlanThought: ThoughtRepresentable {
    private let _text: String

    static var tag: String { "PLAN" }

    init(plan: String) {
        _text = plan
    }

    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_text)\(closingTag)") ]
    }

    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] {
        return [ .string("\(openingTag)\(_text)\(closingTag)") ]
    }
}

struct ActionsThought: ThoughtRepresentable {
    private let _jsonText: String

    static var tag: String { "ACTIONS" }

    var json: String { _jsonText }

    init(json: String) {
        _jsonText = json
    }

    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_jsonText)\(closingTag)") ]
    }

    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] {
        return [ .string("\(openingTag)\(_jsonText)\(closingTag)") ]
    }
}

struct IntermediateResponseThought: ThoughtRepresentable {
    private let _spokenWords: String

    static var tag: String { "INTERMEDIATE_RESPONSE" }

    var wordsToSpeak: String { _spokenWords.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(spokenWords: String) {
        _spokenWords = spokenWords
    }

    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_spokenWords)\(closingTag)") ]
    }

    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] {
        return [ .string("\(openingTag)\(_spokenWords)\(closingTag)") ]
    }
}

struct FinalResponseThought: ThoughtRepresentable {
    private let _spokenWords: String

    static var tag: String { "FINAL_RESPONSE" }

    var wordsToSpeak: String { _spokenWords.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(spokenWords: String) {
        _spokenWords = spokenWords
    }

    func anthropicContent() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_spokenWords)\(closingTag)") ]
    }

    func openAIContent() -> [ChatQuery.ChatCompletionMessageParam.ChatCompletionUserMessageParam.Content] {
        return [ .string("\(openingTag)\(_spokenWords)\(closingTag)") ]
    }
}
