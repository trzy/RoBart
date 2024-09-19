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

import SwiftAnthropic

protocol ThoughtRepresentable {
    static var tag: String { get }
    func content() -> [MessageParameter.Message.Content.ContentObject]
}

extension ThoughtRepresentable {
    var tag: String { Self.tag }

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
    func toClaudeMessage(role: MessageParameter.Message.Role) -> MessageParameter.Message {
        return MessageParameter.Message(role: role, content: .list(self.toClaudeContentObjects()))
    }

    /// Converts an array of `ThoughtRepresentable` objects into an array of `ContentObject`, for
    /// use with Claude.
    /// - Returns: Array of `ContentObject` objects for use with Claude via SwiftAnthropic.
    func toClaudeContentObjects() -> [MessageParameter.Message.Content.ContentObject] {
        return self.flatMap { $0.content() }
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

    init(spokenWords: String, photo: SmartCamera.Photo?) {
        _spokenWords = spokenWords
        _photo = photo
    }

    func content() -> [MessageParameter.Message.Content.ContentObject] {
        var content: [MessageParameter.Message.Content.ContentObject] = [ .text("\(openingTag)\(_spokenWords)") ]
        if let photo = _photo {
            content.append(.text("\(photo.name):"))
            content.append(.image(.init(type: .base64, mediaType: .jpeg, data: photo.jpegBase64)))
        }
        content.append(.text(closingTag))
        return content
    }
}

struct ObservationsThought: ThoughtRepresentable {
    private let _text: String?
    private let _photos: [SmartCamera.Photo]

    static var tag: String { "OBSERVATIONS" }

    init(photos: [SmartCamera.Photo]) {
        _text = nil
        _photos = photos
    }

    init(text: String) {
        _text = text
        _photos = []
    }

    func content() -> [MessageParameter.Message.Content.ContentObject] {
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
}

struct PlanThought: ThoughtRepresentable {
    private let _text: String

    static var tag: String { "PLAN" }

    init(plan: String) {
        _text = plan
    }

    func content() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_text)\(closingTag)") ]
    }
}

struct ActionsThought: ThoughtRepresentable {
    private let _jsonText: String

    static var tag: String { "ACTIONS" }

    init(json: String) {
        _jsonText = json
    }

    func content() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_jsonText)\(closingTag)") ]
    }
}

struct IntermediateResponseThought: ThoughtRepresentable {
    private let _spokenWords: String

    static var tag: String { "INTERMEDIATE_RESPONSE" }

    var wordsToSpeak: String { _spokenWords.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(spokenWords: String) {
        _spokenWords = spokenWords
    }

    func content() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_spokenWords)\(closingTag)") ]
    }
}

struct FinalResponseThought: ThoughtRepresentable {
    private let _spokenWords: String

    static var tag: String { "FINAL_RESPONSE" }

    var wordsToSpeak: String { _spokenWords.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(spokenWords: String) {
        _spokenWords = spokenWords
    }

    func content() -> [MessageParameter.Message.Content.ContentObject] {
        return [ .text("\(openingTag)\(_spokenWords)\(closingTag)") ]
    }
}
