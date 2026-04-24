import AppKit
import Foundation
import AVFoundation
import WebKit

// ── Backend config ────────────────────────────────────────────────────────────

enum BackendType: String {
    case ollama   = "ollama"
    case openai   = "openai"   // NIM, llama.cpp, cualquier OpenAI-compatible
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

// ── Whisper ───────────────────────────────────────────────────────────────────

let WHISPER_BIN = "/usr/local/bin/whisper-cli"

// ── AppDelegate ───────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "⬡"
            button.action = #selector(openMenu)
            button.target = self
        }
        buildMenu()
        addEditMenu()
        try? FileManager.default.createDirectory(
            atPath: NSHomeDirectory() + "/.ollama-chat",
            withIntermediateDirectories: true)
    }

    func addEditMenu() {
        // Required for Cmd+C/V/X/A to work in NSTextField panels
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),        keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),       keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),      keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)),  keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open chat", action: #selector(toggleChat), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Configure backend…", action: #selector(configureBackend), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openMenu() {}
    @objc func toggleChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        chatWindow?.showAndFocus()
    }

    @objc func configureBackend() {
        let cfg = BackendConfig.current
        let alert = NSAlert()
        alert.messageText = "Configure backend"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        // Stack view
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 360, height: 170))
        stack.orientation = .vertical
        stack.alignment   = .left
        stack.spacing     = 10

        // Backend type selector
        let typeRow = NSStackView()
        typeRow.orientation = .horizontal
        typeRow.spacing = 8
        let typeLabel = NSTextField(labelWithString: "Backend:")
        typeLabel.frame.size.width = 70
        let typeSel = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 270, height: 24))
        typeSel.addItem(withTitle: "Ollama")
        typeSel.addItem(withTitle: "OpenAI-compatible (NIM, llama.cpp, LM Studio…)")
        typeSel.selectItem(at: cfg.type == .ollama ? 0 : 1)
        typeRow.addArrangedSubview(typeLabel)
        typeRow.addArrangedSubview(typeSel)

        // NIM checkbox
        let nimRow = NSStackView()
        nimRow.orientation = .horizontal
        nimRow.spacing = 8
        let nimCheck = NSButton(checkboxWithTitle: "Use NVIDIA NIM (integrate.api.nvidia.com)", target: nil, action: nil)
        nimCheck.state = (cfg.url.contains("integrate.api.nvidia.com")) ? .on : .off
        nimRow.addArrangedSubview(nimCheck)

        // URL field
        let urlRow = NSStackView()
        urlRow.orientation = .horizontal
        urlRow.spacing = 8
        let urlLabel = NSTextField(labelWithString: "URL:")
        urlLabel.frame.size.width = 70
        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 270, height: 24))
        urlField.stringValue = cfg.url
        urlField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.placeholderString = "http://localhost:11434"
        urlRow.addArrangedSubview(urlLabel)
        urlRow.addArrangedSubview(urlField)

        // When NIM checkbox toggled, update URL and type fields
        class NimHandler: NSObject {
            weak var urlField: NSTextField?
            weak var typeSel: NSPopUpButton?
            weak var check: NSButton?
            @objc func handle() {
                guard let check = check else { return }
                if check.state == .on {
                    urlField?.stringValue = "https://integrate.api.nvidia.com/v1"
                    typeSel?.selectItem(at: 1)
                } else if urlField?.stringValue == "https://integrate.api.nvidia.com/v1" {
                    urlField?.stringValue = ""
                }
            }
        }
        let nimHandler = NimHandler()
        nimHandler.urlField = urlField
        nimHandler.typeSel  = typeSel
        nimHandler.check    = nimCheck
        objc_setAssociatedObject(nimCheck, "nimHandler", nimHandler, .OBJC_ASSOCIATION_RETAIN)
        nimCheck.target = nimHandler
        nimCheck.action = #selector(NimHandler.handle)

        // API key field
        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.spacing = 8
        let keyLabel = NSTextField(labelWithString: "API key:")
        keyLabel.frame.size.width = 70
        let keyField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 270, height: 24))
        keyField.stringValue = cfg.apiKey
        keyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.placeholderString = "Optional (required for NIM)"
        keyRow.addArrangedSubview(keyLabel)
        keyRow.addArrangedSubview(keyField)

        // Hint
        let hint = NSTextField(labelWithString: "")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.stringValue = backenHint(typeSel.indexOfSelectedItem)
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping
        hint.frame.size.width = 360

        typeSel.target = hint
        // Update hint on change
        let obs = typeSel.observe(\.indexOfSelectedItem) { sel, _ in
            hint.stringValue = self.backenHint(sel.indexOfSelectedItem)
        }

        stack.addArrangedSubview(typeRow)
        stack.addArrangedSubview(nimRow)
        stack.addArrangedSubview(urlRow)
        stack.addArrangedSubview(keyRow)
        stack.addArrangedSubview(hint)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = urlField

        if alert.runModal() == .alertFirstButtonReturn {
            var newCfg = BackendConfig(
                type:   typeSel.indexOfSelectedItem == 0 ? .ollama : .openai,
                url:    urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if newCfg.url.isEmpty {
                newCfg.url = newCfg.type == .ollama ? "http://localhost:11434" : "http://localhost:8080"
            }
            BackendConfig.current = newCfg
            chatWindow?.webView.fetchModels()
        }
        _ = obs
    }

    func backenHint(_ idx: Int) -> String {
        idx == 0
            ? "Default: http://localhost:11434"
            : "NIM: https://integrate.api.nvidia.com/v1\nllama.cpp: http://localhost:8080/v1\nLM Studio: http://localhost:1234/v1"
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// ── ChatWindow ────────────────────────────────────────────────────────────────

class ChatWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebViewWrapper

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 460, height: 620)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        webView = WKWebViewWrapper(frame: frame)
        window.contentView = webView.view
        super.init()
        window.delegate = self
    }

    func showAndFocus() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.sharingType = .none
    }

    func windowWillClose(_ notification: Notification) {}
}

// ── Audio Recorder ────────────────────────────────────────────────────────────

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    var outputURL: URL?
    var onDone: ((URL?) -> Void)?

    func start() {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollama_audio_\(Int(Date().timeIntervalSince1970)).wav")
        outputURL = tmpURL
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        inputNode = engine.inputNode
        guard let input = inputNode else { return }
        let fmt = input.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do { audioFile = try AVAudioFile(forWriting: tmpURL, settings: settings) }
        catch { print("[audio] \(error)"); return }
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            if let c = self.convert(buffer: buffer, to: file.processingFormat) { try? file.write(from: c) }
            else { try? file.write(from: buffer) }
        }
        do { try engine.start() } catch { print("[audio] engine: \(error)") }
    }

    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil; audioFile = nil
        onDone?(outputURL)
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != format,
              let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio    = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?; var done = false
        converter.convert(to: out, error: &error) { _, status in
            if done { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData; done = true; return buffer
        }
        return error == nil ? out : nil
    }
}

// ── Whisper ───────────────────────────────────────────────────────────────────

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

// ── WKWebViewWrapper ──────────────────────────────────────────────────────────

class WKWebViewWrapper: NSObject, WKScriptMessageHandler {
    let view: WKWebView
    let recorder = AudioRecorder()
    var isRecording = false
    var currentStreamSession: URLSession?

    init(frame: NSRect = .zero) {
        let config = WKWebViewConfiguration()
        let cc = WKUserContentController()
        config.userContentController = cc
        view = WKWebView(frame: frame, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        super.init()
        for name in ["sendMessage","loadModels","startRecording","stopRecording","stopStream","checkWhisper"] {
            cc.add(self, name: name)
        }
        loadHTML()
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "sendMessage":
            guard let body = message.body as? [String: String],
                  let prompt = body["prompt"], let model = body["model"] else { return }
            streamResponse(prompt: prompt, model: model)
        case "loadModels":   fetchModels()
        case "checkWhisper": checkWhisperInstall()
        case "startRecording":
            guard !isRecording else { return }
            requestMicAndRecord()
        case "stopStream":
            currentStreamSession?.invalidateAndCancel()
            currentStreamSession = nil
            DispatchQueue.main.async { self.view.evaluateJavaScript("endStream()", completionHandler: nil) }
        case "stopRecording":
            guard isRecording else { return }
            isRecording = false
            recorder.onDone = { [weak self] url in
                guard let self = self, let url = url else {
                    DispatchQueue.main.async { self?.view.evaluateJavaScript("onTranscription(null)", completionHandler: nil) }
                    return
                }
                DispatchQueue.main.async { self.view.evaluateJavaScript("onTranscribing()", completionHandler: nil) }
                transcribe(audioURL: url) { [weak self] text in
                    DispatchQueue.main.async {
                        if let t = text {
                            let esc = t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                            self?.view.evaluateJavaScript("onTranscription('\(esc)')", completionHandler: nil)
                        } else {
                            self?.view.evaluateJavaScript("onTranscription(null)", completionHandler: nil)
                        }
                    }
                }
            }
            recorder.stop()
        default: break
        }
    }

    func requestMicAndRecord() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.startRecording() } }
                else { DispatchQueue.main.async {
                    self?.view.evaluateJavaScript("onMicError('Microphone permission denied.')", completionHandler: nil)
                }}
            }
        default:
            view.evaluateJavaScript("onMicError('Microphone denied. Enable in System Settings > Privacy > Microphone.')", completionHandler: nil)
        }
    }

    func startRecording() {
        isRecording = true
        recorder.start()
        view.evaluateJavaScript("onRecordingStarted()", completionHandler: nil)
    }

    func checkWhisperInstall() {
        let hasBin   = findWhisperBin() != nil
        let hasModel = findWhisperModel() != nil
        view.evaluateJavaScript("onWhisperStatus(\(hasBin),\(hasModel))", completionHandler: nil)
    }

    // ── Fetch models ──────────────────────────────────────────────────────────

    func fetchModels() {
        let cfg = BackendConfig.current
        switch cfg.type {
        case .ollama:  fetchOllamaModels(cfg: cfg)
        case .openai:  fetchOpenAIModels(cfg: cfg)
        }
    }

    func fetchOllamaModels(cfg: BackendConfig) {
        guard let url = URL(string: "\(cfg.url)/api/tags") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }
            let names = models.compactMap { $0["name"] as? String }
            DispatchQueue.main.async {
                self.view.evaluateJavaScript("receiveModels(\(jsonString(names)),'ollama')", completionHandler: nil)
            }
        }.resume()
    }

    func fetchOpenAIModels(cfg: BackendConfig) {
        guard let url = URL(string: "\(cfg.url)/models") else { return }
        var req = URLRequest(url: url)
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else { return }
            let names = models.compactMap { $0["id"] as? String }.sorted()
            DispatchQueue.main.async {
                self.view.evaluateJavaScript("receiveModels(\(jsonString(names)),'openai')", completionHandler: nil)
            }
        }.resume()
    }

    // ── Stream response ───────────────────────────────────────────────────────

    func streamResponse(prompt: String, model: String) {
        let cfg = BackendConfig.current
        switch cfg.type {
        case .ollama: streamOllama(prompt: prompt, model: model, cfg: cfg)
        case .openai: streamOpenAI(prompt: prompt, model: model, cfg: cfg)
        }
    }

    func streamOllama(prompt: String, model: String, cfg: BackendConfig) {
        guard let url = URL(string: "\(cfg.url)/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "stream": true])
        startStream(req: req, parser: OllamaStreamParser())
    }

    func streamOpenAI(prompt: String, model: String, cfg: BackendConfig) {
        guard let url = URL(string: "\(cfg.url)/chat/completions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": true,
            "messages": [["role": "user", "content": prompt]]
        ])
        startStream(req: req, parser: OpenAIStreamParser())
    }

    func startStream(req: URLRequest, parser: StreamParser) {
        currentStreamSession?.invalidateAndCancel()
        let delegate = StreamDelegate(webView: view, parser: parser)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        currentStreamSession = session
        session.dataTask(with: req).resume()
    }

    func loadHTML() { view.loadHTMLString(chatHTML(), baseURL: nil) }
}

// ── Stream parsers ────────────────────────────────────────────────────────────

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
        // SSE format: "data: {...}" or "data: [DONE]"
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

// ── Stream delegate ───────────────────────────────────────────────────────────

class StreamDelegate: NSObject, URLSessionDataDelegate {
    let webView: WKWebView
    let parser:  StreamParser
    var buffer = Data()

    init(webView: WKWebView, parser: StreamParser) {
        self.webView = webView; self.parser = parser
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        let str   = String(data: buffer, encoding: .utf8) ?? ""
        let lines = str.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            guard !line.isEmpty, i < lines.count - 1 else { continue }
            if let token = parser.token(from: line) {
                let escaped = token
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                DispatchQueue.main.async {
                    self.webView.evaluateJavaScript("appendToken(`\(escaped)`)", completionHandler: nil)
                }
            }
        }
        buffer = lines.last.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) } ?? Data()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("endStream()", completionHandler: nil)
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func jsonString(_ arr: [String]) -> String {
    (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
}

// ── HTML ──────────────────────────────────────────────────────────────────────

func chatHTML() -> String { return """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500&display=swap');
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#0d0d0f;--surface:#131316;--border:#1e1e23;
  --text:#d1d1d6;--muted:#3a3a44;--accent:#4ade80;
  --user:#7dd3fc;--error:#f87171;--rec:#f87171;
  --font:'JetBrains Mono','Menlo',monospace;
}
html,body{height:100%;background:var(--bg);color:var(--text);
  font-family:var(--font);font-size:12.5px;line-height:1.6;
  overflow:hidden;-webkit-font-smoothing:antialiased}
#app{display:flex;flex-direction:column;height:100vh;overflow:hidden}
#header{display:flex;align-items:center;justify-content:space-between;
  padding:9px 14px;border-bottom:1px solid var(--border);
  background:var(--surface);-webkit-app-region:drag;user-select:none;flex-shrink:0}
#dot{width:6px;height:6px;border-radius:50%;background:var(--accent);
  box-shadow:0 0 5px var(--accent);animation:pulse 2.5s ease-in-out infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}
#header-left{display:flex;align-items:center;gap:8px}
#backend-badge{font-size:9px;letter-spacing:.06em;text-transform:uppercase;
  color:var(--muted);padding:1px 5px;border:1px solid var(--border);border-radius:3px}
#autoscroll-btn{background:none;border:1px solid var(--border);color:var(--muted);
  font-family:var(--font);font-size:12px;padding:1px 6px;border-radius:3px;
  cursor:pointer;transition:all .15s;line-height:1.4}
#autoscroll-btn.on{border-color:var(--accent);color:var(--accent)}
#autoscroll-btn:hover{border-color:var(--text);color:var(--text)}
#model-wrap{position:relative;display:flex;align-items:center;gap:6px}
#model-btn{background:transparent;border:none;color:var(--muted);
  font-family:var(--font);font-size:11.5px;cursor:pointer;outline:none;
  -webkit-app-region:no-drag;padding:2px 6px;border-radius:3px;
  display:flex;align-items:center;gap:5px;transition:color .15s}
#model-btn:hover{color:var(--text)}
#model-name{color:var(--text)}
#model-dropdown{display:none;position:fixed;top:44px;left:14px;
  background:#1a1a1e;border:1px solid var(--border);border-radius:6px;
  min-width:220px;z-index:999;overflow-y:auto;max-height:calc(100vh - 60px);
  box-shadow:0 8px 24px rgba(0,0,0,.7)}
#model-dropdown.open{display:block}
.model-opt{padding:8px 14px;font-size:11.5px;cursor:pointer;color:var(--text);
  font-family:var(--font);transition:background .1s;white-space:nowrap}
.model-opt:hover{background:var(--border)}
.model-opt.active{color:var(--accent)}
#msgs{flex:1;overflow-y:auto;padding:14px;scroll-behavior:smooth}
#msgs::-webkit-scrollbar{width:3px}
#msgs::-webkit-scrollbar-thumb{background:var(--border);border-radius:2px}
.msg{margin-bottom:16px;animation:fadein .15s ease}
@keyframes fadein{from{opacity:0;transform:translateY(3px)}to{opacity:1;transform:none}}
.lbl{font-size:10px;letter-spacing:.07em;text-transform:uppercase;margin-bottom:3px;color:var(--muted)}
.msg.user .lbl{color:var(--user)}
.msg.ai .lbl{color:var(--accent)}
.msg.err .lbl{color:var(--error)}
.body{white-space:pre-wrap;word-break:break-word}
.msg.user .body{color:var(--user)}
.msg.err .body{color:var(--error)}
.cursor::after{content:'▋';color:var(--accent);animation:blink .65s step-end infinite;margin-left:1px}
@keyframes blink{0%,100%{opacity:1}50%{opacity:0}}
#bottom{border-top:1px solid var(--border);background:var(--surface);
  padding:9px 14px;display:flex;align-items:flex-end;gap:6px;flex-shrink:0}
#inp{flex:1;background:transparent;border:none;color:var(--text);
  font-family:var(--font);font-size:12.5px;outline:none;resize:none;
  line-height:1.5;max-height:72px;overflow-y:auto;caret-color:var(--accent)}
#inp::placeholder{color:var(--muted)}
.action-btn{background:none;border:1px solid var(--border);color:var(--muted);
  font-family:var(--font);font-size:13px;padding:3px 8px;border-radius:4px;
  cursor:pointer;transition:all .15s;flex-shrink:0;margin-bottom:1px;line-height:1}
.action-btn:hover{border-color:var(--accent);color:var(--accent)}
#mic-btn{font-size:14px;padding:3px 7px}
#mic-btn.recording{border-color:var(--rec);color:var(--rec);animation:recpulse 1s ease-in-out infinite}
#mic-btn.transcribing{border-color:var(--muted);color:var(--muted);cursor:default}
@keyframes recpulse{0%,100%{box-shadow:0 0 0 0 rgba(248,113,113,.4)}50%{box-shadow:0 0 0 4px rgba(248,113,113,0)}}
#btn.stopping{border-color:var(--error);color:var(--error)}
#hint{font-size:10px;color:var(--muted);padding:4px 14px 0;display:none;letter-spacing:.03em}
#hint.visible{display:block}
</style>
</head>
<body>
<div id="app">
  <div id="header">
    <div id="header-left">
      <div id="dot"></div>
      <div id="model-wrap">
        <button id="model-btn">
          <span id="model-name">loading…</span>
          <span style="color:var(--muted);font-size:9px">▾</span>
        </button>
        <div id="model-dropdown"></div>
      </div>
      <span id="backend-badge">ollama</span>
    </div>
    <button id="autoscroll-btn" title="Auto-scroll" style="-webkit-app-region:no-drag">↓</button>
  </div>
  <div id="msgs"></div>
  <div id="hint"></div>
  <div id="bottom">
    <textarea id="inp" placeholder="Message… (Enter to send)" rows="1"></textarea>
    <button id="mic-btn" class="action-btn" title="Click to record">🎙</button>
    <button id="btn" class="action-btn">↵</button>
  </div>
</div>
<script>
let model = '', busy = false, currentBody = null;
let micState = 'idle', streaming = false;
let autoScroll = true;

window.webkit.messageHandlers.loadModels.postMessage({});
window.webkit.messageHandlers.checkWhisper.postMessage({});

// ── Model dropdown ────────────────────────────────────────────────────────────
const modelBtn      = document.getElementById('model-btn');
const modelName     = document.getElementById('model-name');
const modelDropdown = document.getElementById('model-dropdown');
const backendBadge  = document.getElementById('backend-badge');

modelBtn.addEventListener('click', e => { e.stopPropagation(); modelDropdown.classList.toggle('open'); });
document.addEventListener('click', () => modelDropdown.classList.remove('open'));

// ── Auto-scroll toggle ────────────────────────────────────────────────────────
const autoscrollBtn = document.getElementById('autoscroll-btn');
autoscrollBtn.classList.toggle('on', autoScroll);

autoscrollBtn.addEventListener('click', e => {
  e.stopPropagation();
  autoScroll = !autoScroll;
  autoscrollBtn.classList.toggle('on', autoScroll);
  autoscrollBtn.title = autoScroll ? 'Auto-scroll: on' : 'Auto-scroll: off';
  if (autoScroll) {
    const msgs = document.getElementById('msgs');
    msgs.scrollTop = msgs.scrollHeight;
  }
});

// Pause auto-scroll if user scrolls up manually
document.getElementById('msgs').addEventListener('scroll', () => {
  const msgs = document.getElementById('msgs');
  const atBottom = msgs.scrollHeight - msgs.scrollTop - msgs.clientHeight < 40;
  if (!atBottom && streaming) {
    autoScroll = false;
    autoscrollBtn.classList.remove('on');
  }
});

function receiveModels(models, backend) {
  backendBadge.textContent = backend;
  if (!models.length) { modelName.textContent = 'no models'; return; }
  if (!model) model = models[0];
  const match = models.find(m => m === model || m.startsWith(model.split(':')[0]));
  model = match || models[0];
  modelName.textContent = model.split(':')[0];
  modelDropdown.innerHTML = '';
  models.forEach(m => {
    const div = document.createElement('div');
    div.className = 'model-opt' + (m === model ? ' active' : '');
    div.textContent = m;
    div.addEventListener('click', e => {
      e.stopPropagation(); model = m;
      modelName.textContent = m.split(':')[0];
      modelDropdown.querySelectorAll('.model-opt').forEach(el => el.classList.toggle('active', el.textContent === m));
      modelDropdown.classList.remove('open');
    });
    modelDropdown.appendChild(div);
  });
}

// ── Whisper ───────────────────────────────────────────────────────────────────
function onWhisperStatus(hasBin, hasModel) {
  const hint = document.getElementById('hint');
  if (!hasBin) { hint.textContent = '⚠ whisper-cli not found. Install: brew install whisper-cpp'; hint.classList.add('visible'); }
  else if (!hasModel) { hint.textContent = '⚠ Whisper model not found. Download ggml-base.bin to /opt/homebrew/share/whisper-cpp/'; hint.classList.add('visible'); }
}

// ── Mic ───────────────────────────────────────────────────────────────────────
const micBtn = document.getElementById('mic-btn');
const btn    = document.getElementById('btn');

micBtn.addEventListener('click', e => {
  e.preventDefault();
  if (micState === 'idle') {
    micState = 'recording';
    micBtn.classList.add('recording');
    micBtn.title = 'Click to stop';
    window.webkit.messageHandlers.startRecording.postMessage({});
  } else if (micState === 'recording') {
    micBtn.classList.remove('recording');
    micBtn.title = 'Click to record';
    window.webkit.messageHandlers.stopRecording.postMessage({});
  }
});

btn.addEventListener('click', e => {
  e.preventDefault();
  if (streaming) {
    window.webkit.messageHandlers.stopStream.postMessage({});
    streaming = false; busy = false;
    if (currentBody) currentBody.classList.remove('cursor');
    currentBody = null;
    btn.textContent = '↵'; btn.classList.remove('stopping');
    return;
  }
  send();
});

function onRecordingStarted() { micState = 'recording'; }

function onTranscribing() {
  micState = 'transcribing';
  micBtn.classList.remove('recording');
  micBtn.classList.add('transcribing');
  micBtn.textContent = '⏳';
}

function onTranscription(text) {
  micState = 'idle';
  micBtn.classList.remove('recording','transcribing');
  micBtn.textContent = '🎙';
  if (text && text.trim()) sendText(text.trim());
}

function onMicError(msg) {
  micState = 'idle';
  micBtn.classList.remove('recording','transcribing');
  micBtn.textContent = '🎙';
  addMsg('err').textContent = msg;
}

// ── Chat ──────────────────────────────────────────────────────────────────────
function addMsg(role) {
  const c = document.getElementById('msgs'), d = document.createElement('div');
  d.className = 'msg ' + role;
  const L = {user:'you', ai:model.split(':')[0], err:'error'};
  d.innerHTML = '<div class="lbl">' + (L[role]||role) + '</div><div class="body"></div>';
  c.appendChild(d); c.scrollTop = c.scrollHeight;
  return d.querySelector('.body');
}

function appendToken(t) {
  if (!currentBody) return;
  currentBody.textContent += t;
  if (autoScroll) {
    const msgs = document.getElementById('msgs');
    msgs.scrollTop = msgs.scrollHeight;
  }
}

function endStream() {
  if (currentBody) currentBody.classList.remove('cursor');
  currentBody = null; busy = false; streaming = false;
  btn.textContent = '↵'; btn.classList.remove('stopping');
}

function sendText(text) {
  if (busy || !text) return;
  modelDropdown.classList.remove('open');
  addMsg('user').textContent = text;
  currentBody = addMsg('ai');
  currentBody.classList.add('cursor');
  busy = true; streaming = true;
  btn.textContent = '⏹'; btn.classList.add('stopping');
  window.webkit.messageHandlers.sendMessage.postMessage({prompt: text, model: model});
}

function send() {
  const inp = document.getElementById('inp'), text = inp.value.trim();
  if (!text) return;
  inp.value = ''; inp.style.height = 'auto';
  sendText(text);
}

document.getElementById('inp').addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
  setTimeout(() => { e.target.style.height = 'auto'; e.target.style.height = Math.min(e.target.scrollHeight, 72) + 'px'; }, 0);
});
</script>
</body>
</html>
""" }

// ── Entry point ───────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()