import Foundation

let WHISPER_BIN = "/usr/local/bin/whisper-cli"

func findWhisperBin() -> String? {
    [WHISPER_BIN, "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        .first { FileManager.default.fileExists(atPath: $0) }
}

func findWhisperModel() -> String? {
    let dirs = [
        "/opt/homebrew/share/whisper-cpp",
        "/opt/homebrew/share/whisper-cpp/models",
        "/usr/local/share/whisper-cpp",
        NSHomeDirectory() + "/.cache/whisper",
        NSHomeDirectory() + "/.ollama-chat",
    ]
    let preferred = ["ggml-base.en.bin","ggml-base.bin","ggml-small.bin","ggml-tiny.bin","ggml-medium.bin"]
    for dir in dirs {
        for name in preferred {
            let p = dir + "/" + name
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir),
           let m = files.first(where: { $0.hasSuffix(".bin") && $0.contains("ggml") }) {
            return dir + "/" + m
        }
    }
    return nil
}

func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
    guard let bin   = findWhisperBin(),
          let model = findWhisperModel() else { completion(nil); return }
    print("[whisper] \(bin) model=\(model)")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: bin)
    task.arguments = ["--model", model, "--language", "auto", "--output-txt", "--no-prints", "--file", audioURL.path]
    let pipe = Pipe()
    task.standardOutput = pipe; task.standardError = Pipe()
    task.terminationHandler = { _ in
        let txtURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
        if let text = try? String(contentsOf: txtURL, encoding: .utf8) {
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: txtURL)
            try? FileManager.default.removeItem(at: audioURL)
            completion(cleaned.isEmpty ? nil : cleaned)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: audioURL)
            completion(text.isEmpty ? nil : text)
        }
    }
    do { try task.run() } catch { print("[whisper] \(error)"); completion(nil) }
}
