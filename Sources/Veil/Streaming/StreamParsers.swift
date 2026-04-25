import Foundation

protocol StreamParser {
    func token(from line: String) -> String?
}

struct OllamaStreamParser: StreamParser {
    func token(from line: String) -> String? {
        guard let d = line.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return nil }
        // /api/chat format
        if let msg = j["message"] as? [String: Any] { return msg["content"] as? String }
        // /api/generate fallback
        return j["response"] as? String
    }
}

struct AnthropicStreamParser: StreamParser {
    func token(from line: String) -> String? {
        var s = line
        if s.hasPrefix("data:") { s = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        if s.isEmpty { return nil }
        guard let d = s.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              (j["type"] as? String) == "content_block_delta",
              let delta = j["delta"] as? [String: Any],
              (delta["type"] as? String) == "text_delta"
        else { return nil }
        return delta["text"] as? String
    }
}

struct OpenAIStreamParser: StreamParser {
    func token(from line: String) -> String? {
        var s = line
        if s.hasPrefix("data:") { s = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        if s == "[DONE]" || s.isEmpty { return nil }
        guard let d = s.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let choices = j["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any]
        else { return nil }
        return delta["content"] as? String
    }
}
