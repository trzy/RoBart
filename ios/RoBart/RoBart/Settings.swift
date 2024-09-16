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

    @Published var anthropicAPIKey: String = "" {
        didSet {
            // API key is saved
            UserDefaults.standard.set(anthropicAPIKey, forKey: Self.k_anthropicAPIKey)
            log("Set: \(Self.k_anthropicAPIKey) = \(anthropicAPIKey)")
        }
    }

    @Published var driveToButtonUsesNavigation = true

    private static let k_roleKey = "role"
    private static let k_anthropicAPIKey = "anthropic_api_key"

    fileprivate init() {
        if let value = UserDefaults.standard.string(forKey: Self.k_roleKey),
           let role = Role(rawValue: value) {
            self.role = role
        }
    }
}

fileprivate func log(_ message: String) {
    print("[Settings] \(message)")
}
