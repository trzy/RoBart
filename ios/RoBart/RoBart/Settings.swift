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
            UserDefaults.standard.set(role.rawValue, forKey: Self.k_roleKey)
            log("Set: \(Self.k_roleKey) = \(role)")
        }
    }

    private static let k_roleKey = "role"

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
