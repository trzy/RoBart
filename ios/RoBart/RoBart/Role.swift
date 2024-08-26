//
//  Role.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 8/26/24.
//

import Foundation

enum Role: String, CaseIterable, Identifiable {
    case robot
    case phone

    var id: Self {
        return self
    }
}
