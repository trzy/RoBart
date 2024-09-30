//
//  Memory.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/29/24.
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
