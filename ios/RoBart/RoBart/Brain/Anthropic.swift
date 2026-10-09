//
//  Anthropic.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/8/26.
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

/// Minimal client for the Claude Messages API (https://platform.claude.com/docs/en/api/messages).
///
/// Only the subset of the API that RoBart uses is modeled. Every response retains its raw JSON
/// body so that fields not modeled here can still be inspected for debugging.
class Anthropic {
    // MARK: Request types

    struct Message: Encodable {
        enum Role: String, Encodable {
            case user
            case assistant
        }

        let role: Role
        let content: [Content]
    }

    enum Content: Encodable {
        case text(String)
        case image(mediaType: String, base64Data: String)

        static func jpeg(base64Data: String) -> Content {
            return .image(mediaType: "image/jpeg", base64Data: base64Data)
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case source
        }

        private struct ImageSource: Encodable {
            let type = "base64"
            let mediaType: String
            let data: String

            private enum CodingKeys: String, CodingKey {
                case type
                case mediaType = "media_type"
                case data
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let mediaType, let base64Data):
                try container.encode("image", forKey: .type)
                try container.encode(ImageSource(mediaType: mediaType, data: base64Data), forKey: .source)
            }
        }
    }

    struct MessageRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [Message]
        let stopSequences: [String]?

        init(model: String, maxTokens: Int, system: String? = nil, messages: [Message], stopSequences: [String]? = nil) {
            self.model = model
            self.maxTokens = maxTokens
            self.system = system
            self.messages = messages
            self.stopSequences = stopSequences
        }

        private enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
            case stopSequences = "stop_sequences"
        }
    }

    // MARK: Response types

    enum ResponseContent: Decodable {
        case text(String)
        case thinking(String)
        case other(type: String)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case thinking
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try container.decode(String.self, forKey: .text))
            case "thinking":
                self = .thinking(try container.decodeIfPresent(String.self, forKey: .thinking) ?? "")
            default:
                self = .other(type: type)
            }
        }
    }

    /// Populated only when `stopReason == "refusal"`.
    struct StopDetails: Decodable {
        let type: String
        let category: String?
        let explanation: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }

    struct MessageResponse: Decodable {
        let id: String
        let model: String
        let content: [ResponseContent]
        let stopReason: String?
        let stopSequence: String?
        let stopDetails: StopDetails?
        let usage: Usage

        /// Value of the `request-id` response header, useful when reporting issues to Anthropic.
        fileprivate(set) var requestID: String?

        /// The undecoded JSON response body.
        fileprivate(set) var rawResponse = Data()

        var rawResponseString: String {
            return String(data: rawResponse, encoding: .utf8) ?? ""
        }

        /// All text blocks concatenated, skipping thinking and other block types.
        var text: String {
            return content.compactMap {
                if case let .text(text) = $0 { return text }
                return nil
            }.joined()
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case model
            case content
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
            case stopDetails = "stop_details"
            case usage
        }
    }

    enum AnthropicError: LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, type: String?, message: String?, requestID: String?, rawResponse: Data)
        case decodingFailed(underlyingError: Error, requestID: String?, rawResponse: Data)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Anthropic API returned a non-HTTP response"
            case .apiError(let statusCode, let type, let message, _, let rawResponse):
                if let message = message {
                    return "Anthropic API error \(statusCode) (\(type ?? "unknown")): \(message)"
                }
                return "Anthropic API error \(statusCode): \(String(data: rawResponse, encoding: .utf8) ?? "")"
            case .decodingFailed(let underlyingError, _, _):
                return "Failed to decode Anthropic API response: \(underlyingError)"
            }
        }
    }

    // MARK: Client

    private struct ErrorResponse: Decodable {
        struct Details: Decodable {
            let type: String?
            let message: String?
        }

        let error: Details
    }

    private let _apiKey: String
    private let _baseURL: URL
    private let _timeout: TimeInterval
    private let _session: URLSession
    private let _apiVersion = "2023-06-01"

    init(apiKey: String, baseURL: URL = URL(string: "https://api.anthropic.com")!, timeout: TimeInterval = 600, session: URLSession = .shared) {
        _apiKey = apiKey
        _baseURL = baseURL
        _timeout = timeout
        _session = session
    }

    func createMessage(_ messageRequest: MessageRequest, betas: [String] = []) async throws -> MessageResponse {
        var request = URLRequest(url: _baseURL.appendingPathComponent("v1/messages"), timeoutInterval: _timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(_apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(_apiVersion, forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(messageRequest)

        let (data, response) = try await _session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }
        let requestID = httpResponse.value(forHTTPHeaderField: "request-id")

        guard httpResponse.statusCode == 200 else {
            let details = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw AnthropicError.apiError(statusCode: httpResponse.statusCode, type: details?.type, message: details?.message, requestID: requestID, rawResponse: data)
        }

        do {
            var messageResponse = try JSONDecoder().decode(MessageResponse.self, from: data)
            messageResponse.requestID = requestID
            messageResponse.rawResponse = data
            return messageResponse
        } catch {
            throw AnthropicError.decodingFailed(underlyingError: error, requestID: requestID, rawResponse: data)
        }
    }
}
