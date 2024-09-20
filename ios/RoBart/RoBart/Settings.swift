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
            UserDefaults.standard.set(role.rawValue, forKey: Self.k_modelKey)
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

    @Published var driveToButtonUsesNavigation = true

    private static let k_roleKey = "role"
    private static let k_modelKey = "model"
    private static let k_anthropicAPIKey = "anthropic_api_key"
    private static let k_openAIAPIKey = "openai_api_key"
    private static let k_deepgramAPIKey = "deepgram_api_key"

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
    }
}

fileprivate func log(_ message: String) {
    print("[Settings] \(message)")
}
