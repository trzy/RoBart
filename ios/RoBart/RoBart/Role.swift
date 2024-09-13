//
//  Role.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import Foundation

enum Role: String, Codable, SimpleBinaryCodable, CaseIterable, Identifiable {
    case robot
    case handheld

    var id: Self {
        return self
    }
}
