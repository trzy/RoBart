//
//  Settings.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import Combine
import Foundation

class Settings: ObservableObject {
    static let shared = Settings()

    @Published var role: Role = .robot {
        didSet {
            // Role is saved
            UserDefaults.standard.set(role.rawValue, forKey: Self.k_roleKey)
            log("Set: \(Self.k_roleKey) = \(role)")
        }
    }

    @Published var model: Brain.Model = .claude35Sonnet {
        didSet {
            // Model is saved
            UserDefaults.standard.set(model.rawValue, forKey: Self.k_modelKey)
            log("Set: \(Self.k_modelKey) = \(model)")
        }
    }

    @Published var anthropicAPIKey: String = "" {
        didSet {
            // API key is saved
            UserDefaults.standard.set(anthropicAPIKey, forKey: Self.k_anthropicAPIKey)
            log("Set: \(Self.k_anthropicAPIKey) = <redacted>")
        }
    }

    @Published var openAIAPIKey: String = "" {
        didSet {
            // API key is saved
            UserDefaults.standard.set(openAIAPIKey, forKey: Self.k_openAIAPIKey)
            log("Set: \(Self.k_openAIAPIKey) = <redacted>")
        }
    }

    @Published var deepgramAPIKey: String = "" {
        didSet {
            // API key is saved
            UserDefaults.standard.set(deepgramAPIKey, forKey: Self.k_deepgramAPIKey)
            log("Set: \(Self.k_deepgramAPIKey) = <redacted>")
        }
    }

    @Published var followDistance: Float = 1.3 {
        didSet {
            UserDefaults.standard.set(followDistance, forKey: Self.k_followDistanceKey)
            log("Set: \(Self.k_followDistanceKey) = \(followDistance)")
        }
    }

    @Published var maxPersonDistance: Float = 3 {
        didSet {
            UserDefaults.standard.set(maxPersonDistance, forKey: Self.k_maxPersonDistanceKey)
            log("Set: \(Self.k_maxPersonDistanceKey) = \(maxPersonDistance)")
        }
    }

    @Published var personDetectionHz: Double = 2 {
        didSet {
            UserDefaults.standard.set(personDetectionHz, forKey: Self.k_personDetectionHz)
            log("Set: \(Self.k_personDetectionHz) = \(personDetectionHz)")
        }
    }

    @Published var driveToButtonUsesNavigation = true

    private static let k_roleKey = "role"
    private static let k_modelKey = "model"
    private static let k_anthropicAPIKey = "anthropic_api_key"
    private static let k_openAIAPIKey = "openai_api_key"
    private static let k_deepgramAPIKey = "deepgram_api_key"
    private static let k_followDistanceKey = "follow_distance"
    private static let k_maxPersonDistanceKey = "max_person_distance"
    private static let k_personDetectionHz = "person_detection_hz"

    fileprivate init() {
        if let value = UserDefaults.standard.string(forKey: Self.k_roleKey),
           let role = Role(rawValue: value) {
            self.role = role
        }

        if let value = UserDefaults.standard.string(forKey: Self.k_modelKey),
           let model = Brain.Model(rawValue: value) {
            self.model = model
        }

        if let value = UserDefaults.standard.string(forKey: Self.k_anthropicAPIKey) {
            self.anthropicAPIKey = value
        }

        if let value = UserDefaults.standard.string(forKey: Self.k_openAIAPIKey) {
            self.openAIAPIKey = value
        }

        if let value = UserDefaults.standard.string(forKey: Self.k_deepgramAPIKey) {
            self.deepgramAPIKey = value
        }

        if let followDistance = UserDefaults.standard.object(forKey: Self.k_followDistanceKey) as? Float {
            self.followDistance = followDistance
        }

        if let maxPersonDistance = UserDefaults.standard.object(forKey: Self.k_maxPersonDistanceKey) as? Float {
            self.maxPersonDistance = maxPersonDistance
        }

        if let personDetectionHz = UserDefaults.standard.object(forKey: Self.k_personDetectionHz) as? Double {
            self.personDetectionHz = personDetectionHz
        }
    }
}

fileprivate func log(_ message: String) {
    print("[Settings] \(message)")
}
