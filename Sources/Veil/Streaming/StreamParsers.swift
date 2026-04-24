import Foundation

protocol StreamParser {
    func token(from line: String) -> String?
}

struct OllamaStreamParser: StreamParser {
    func token(from line: String) -> String? {
        guard let d = line.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return nil }
        return j["response"] as? String
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
