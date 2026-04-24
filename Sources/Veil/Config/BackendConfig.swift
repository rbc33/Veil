import Foundation

enum BackendType: String {
    case ollama = "ollama"
    case openai = "openai"
}

struct BackendConfig {
    var type:   BackendType
    var url:    String
    var apiKey: String

    static var current: BackendConfig {
        get {
            let d = UserDefaults.standard
            return BackendConfig(
                type:   BackendType(rawValue: d.string(forKey: "backendType") ?? "") ?? .ollama,
                url:    d.string(forKey: "backendURL")    ?? "http://localhost:11434",
                apiKey: d.string(forKey: "backendAPIKey") ?? ""
            )
        }
        set {
            let d = UserDefaults.standard
            d.set(newValue.type.rawValue, forKey: "backendType")
            d.set(newValue.url,           forKey: "backendURL")
            d.set(newValue.apiKey,        forKey: "backendAPIKey")
        }
    }
}
