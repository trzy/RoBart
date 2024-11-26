//
//  Memory.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/29/24.
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

import Foundation

struct Memory: Codable {
    let pointNumber: Int
    let description: String
}

func decodeMemories(from json: String) -> [Memory]? {
    guard let jsonData = json.data(using: .utf8) else { return nil }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode([Memory].self, from: jsonData)
    } catch {
        print("[Memory] Error decoding JSON: \(error)")
    }

    return nil
}
