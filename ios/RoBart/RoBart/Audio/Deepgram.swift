//
//  Deepgram.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 9/17/24.
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

/// Uploads audio bytes to Deepgram and produces a transcript.
/// - Parameter sampleData: Audio bytes in single-channel 16 KHz signed 16-bit PCM format.
/// - Returns: Transcript text if successful otherwise `nil`.
func uploadAudioToDeepgram(_ sampleData: Data) async -> String? {
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

fileprivate func log(_ message: String) {
    print("[Deepgram] \(message)")
}
