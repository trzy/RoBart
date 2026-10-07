//
//  MistralResponseMiddleware.swift
//  RoBart
//
//  Created by Bart Trzynadlowski on 10/6/26.
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
import OpenAI

/// Rewrites Mistral chat completion responses so the OpenAI library can decode them.
///
/// When reasoning is enabled, Mistral returns `message.content` as a list of chunks rather than
/// a string:
///
///     "content": [
///         { "type": "thinking", "thinking": [ { "type": "text", "text": "..." } ] },
///         { "type": "text", "text": "..." }
///     ]
///
/// The OpenAI library expects a string. We flatten the text chunks into `content` and move the
/// thinking text to `reasoning_content`, which the library exposes as `message.reasoning`.
/// Responses that are already in the expected format are passed through untouched.
struct MistralResponseMiddleware: OpenAIMiddleware {
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        guard let data = data,
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var choices = json["choices"] as? [[String: Any]] else {
            return (response, data)
        }

        var modified = false
        for i in choices.indices {
            guard var message = choices[i]["message"] as? [String: Any],
                  let chunks = message["content"] as? [[String: Any]] else {
                continue
            }
            let text = chunks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            let thinking = chunks.filter { $0["type"] as? String == "thinking" }.map { Self.thinkingText(from: $0["thinking"]) }.joined()
            message["content"] = text
            if !thinking.isEmpty {
                message["reasoning_content"] = thinking
            }
            choices[i]["message"] = message
            modified = true
        }

        guard modified else { return (response, data) }
        json["choices"] = choices
        guard let rewrittenData = try? JSONSerialization.data(withJSONObject: json) else {
            return (response, data)
        }
        return (response, rewrittenData)
    }

    /// Thinking content is documented as a list of text chunks but we accept a plain string, too.
    private static func thinkingText(from value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        if let chunks = value as? [[String: Any]] {
            return chunks.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }
}
