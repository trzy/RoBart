//
//  Brain.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
//

import Foundation

class Brain {
    static let shared = Brain()

    private let _speechDetector = SpeechDetector()

    fileprivate init() {
        if Settings.shared.role == .robot {
            _speechDetector.startListening()
        }
    }
}
