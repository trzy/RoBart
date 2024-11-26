//
//  Settings.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
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

class Settings: ObservableObject {
    static let shared = Settings()

    @Published var role: Role = .robot {
        didSet {
            // Role is saved
            UserDefaults.standard.set(role.rawValue, forKey: Self.k_roleKey)
            log("Set: \(Self.k_roleKey) = \(role)")
        }
    }

    @Published var watchEnabled = false {
        didSet {
            // Watch enabled is saved
            UserDefaults.standard.set(watchEnabled, forKey: Self.k_watchKey)
            log("Set: \(Self.k_watchKey) = \(watchEnabled)")
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
            UserDefaults.standard.set(personDetectionHz, forKey: Self.k_personDetectionHzKey)
            log("Set: \(Self.k_personDetectionHzKey) = \(personDetectionHz)")
        }
    }

    @Published var recordVideos = true {
        didSet {
            UserDefaults.standard.set(recordVideos, forKey: Self.k_recordVideosKey)
            log("Set: \(Self.k_recordVideosKey) = \(recordVideos)")
        }
    }

    @Published var annotateVideos = true {
        didSet {
            UserDefaults.standard.set(annotateVideos, forKey: Self.k_annotateVideosKey)
            log("Set: \(Self.k_annotateVideosKey) = \(annotateVideos)")
        }
    }

    @Published var driveToButtonUsesNavigation = true

    private static let k_roleKey = "role"
    private static let k_watchKey = "watch"
    private static let k_modelKey = "model"
    private static let k_anthropicAPIKey = "anthropic_api_key"
    private static let k_openAIAPIKey = "openai_api_key"
    private static let k_deepgramAPIKey = "deepgram_api_key"
    private static let k_followDistanceKey = "follow_distance"
    private static let k_maxPersonDistanceKey = "max_person_distance"
    private static let k_personDetectionHzKey = "person_detection_hz"
    private static let k_recordVideosKey = "record_videos"
    private static let k_annotateVideosKey = "annotate_videos"

    fileprivate init() {
        if let value = UserDefaults.standard.string(forKey: Self.k_roleKey),
           let role = Role(rawValue: value) {
            self.role = role
        }

        if let watchEnabled = UserDefaults.standard.object(forKey: Self.k_watchKey) as? Bool {
            self.watchEnabled = watchEnabled
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

        if let personDetectionHz = UserDefaults.standard.object(forKey: Self.k_personDetectionHzKey) as? Double {
            self.personDetectionHz = personDetectionHz
        }

        if let recordVideos = UserDefaults.standard.object(forKey: Self.k_recordVideosKey) as? Bool {
            self.recordVideos = recordVideos
        }

        if let annotateVideos = UserDefaults.standard.object(forKey: Self.k_annotateVideosKey) as? Bool {
            self.annotateVideos = annotateVideos
        }
    }
}

fileprivate func log(_ message: String) {
    print("[Settings] \(message)")
}
