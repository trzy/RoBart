//
//  Deepgram.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
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

import AVFoundation

struct DeepgramV1ListenResponse: Codable {
    let results: Results

    struct Results: Codable {
        let channels: [Channel]
    }

    struct Channel: Codable {
        let alternatives: [Alternative]
    }

    struct Alternative: Codable {
        let transcript: String
    }
}

fileprivate let _jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

/// Transcribes audio to text using Deepgram.
/// - Parameter sampleData: Audio bytes in single-channel 16 KHz signed 16-bit PCM format.
/// - Returns: Transcript text if successful otherwise `nil`.
func transcribeWithDeepgram(_ sampleData: Data) async -> String? {
    let url = URL(string: "https://api.deepgram.com/v1/listen?encoding=linear16&channels=1&sample_rate=16000")!
    var request = URLRequest(url: url)
    request.addValue("Token \(Settings.shared.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
    request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    do {
        let (data, response) = try await URLSession.shared.upload(for: request, from: sampleData)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            log("Error: Upload failed")
            return nil
        }
        do {
            let response = try _jsonDecoder.decode(DeepgramV1ListenResponse.self, from: data)
            if let transcript = response.results.channels.first?.alternatives.first?.transcript {
                return transcript
            }
        } catch {
            log("Error: Unable to decode response: \(error)")
        }
    } catch {
        log("Error: Upload failed: \(error.localizedDescription)")
    }

    return nil
}

/// Converts text to synthesized speech using Deepgram.
/// - Parameter text: Text to vocalize.
/// - Returns: MP3 file data if successful, otherwise `nil`.
func vocalizeWithDeepgram(_ text: String) async -> Data? {
    guard let url = URL(string: "https://api.deepgram.com/v1/speak?model=aura-orpheus-en") else { return nil }
    var request = URLRequest(url: url)
    request.addValue("Token \(Settings.shared.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"

    guard let requestBody = try? JSONEncoder().encode([ "text": text ]) else {
        log("Error: Unable to encode request body")
        return nil
    }

    do {
        let (data, response) = try await URLSession.shared.upload(for: request, from: requestBody)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            log("Error: Upload failed")
            return nil
        }
        log("Received voice: \(data.count) bytes")
        return data

    } catch {
        log("Error: Upload failed: \(error.localizedDescription)")
    }

    return nil
}

fileprivate func log(_ message: String) {
    print("[Deepgram] \(message)")
}
