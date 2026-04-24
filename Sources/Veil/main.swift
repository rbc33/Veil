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

// ── PrivateDropdown ───────────────────────────────────────────────────────────

class PrivateDropdown: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let button: NSButton
    private let panel: NSPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    var items: [String] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
        }
    }
    var selected: String = "" { didSet { updateButtonTitle() } }
    var onSelect: ((String) -> Void)?

    override init() {
        button = NSButton(title: "—  ▾", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        button.frame = NSRect(x: 0, y: 0, width: 220, height: 24)

        let col = NSTableColumn(identifier: .init("item"))
        col.width = 240
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsEmptySelection = false
        tableView.usesAlternatingRowBackgroundColors = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 200),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        panel.sharingType = .none
        panel.backgroundColor = NSColor.controlBackgroundColor
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        super.init()
        panel.contentView = scrollView
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        button.target = self
        button.action = #selector(toggle)
    }

    private func updateButtonTitle() {
        button.title = (selected.isEmpty ? "—" : selected) + "  ▾"
    }

    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil); return }
        tableView.reloadData()
        guard let win = button.window else { return }
        let bf = button.convert(button.bounds, to: nil)
        let sf = win.convertToScreen(bf)
        let rowH: CGFloat = 22
        let h = min(CGFloat(max(items.count, 1)) * rowH + 2, 220)
        let w = max(sf.width, 260)
        panel.setFrame(NSRect(x: sf.minX, y: sf.minY - h, width: w, height: h), display: true)
        tableView.frame = NSRect(x: 0, y: 0, width: w, height: CGFloat(items.count) * rowH)
        if let idx = items.firstIndex(of: selected) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        }
        win.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func rowClicked() {
        let idx = tableView.clickedRow
        guard idx >= 0, idx < items.count else { return }
        selected = items[idx]
        onSelect?(selected)
        close()
    }

    func close() {
        if let parent = panel.parent { parent.removeChildWindow(panel) }
        panel.orderOut(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tf = NSTextField(labelWithString: items[row])
        tf.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.identifier = .init("cell")
        return tf
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let v = NSTableRowView()
        return v
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
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 360, height: 260))
        stack.orientation = .vertical
        stack.alignment   = .left
        stack.spacing     = 10

        // Backend type selector (NSSegmentedControl — no popup window)
        let typeRow = NSStackView()
        typeRow.orientation = .horizontal
        typeRow.spacing = 8
        let typeLabel = NSTextField(labelWithString: "Backend:")
        typeLabel.frame.size.width = 70
        let typeSeg = NSSegmentedControl(labels: ["Ollama", "OpenAI-compatible"], trackingMode: .selectOne, target: nil, action: nil)
        typeSeg.selectedSegment = cfg.type == .ollama ? 0 : 1
        typeRow.addArrangedSubview(typeLabel)
        typeRow.addArrangedSubview(typeSeg)

        // Quick-fill checkboxes
        let nimRow = NSStackView()
        nimRow.orientation = .horizontal
        nimRow.spacing = 16

        let nimCheck = NSButton(checkboxWithTitle: "NVIDIA NIM", target: nil, action: nil)
        nimCheck.state = cfg.url.contains("integrate.api.nvidia.com") ? .on : .off

        let oaiCheck = NSButton(checkboxWithTitle: "OpenAI", target: nil, action: nil)
        oaiCheck.state = cfg.url.contains("api.openai.com") ? .on : .off

        nimRow.addArrangedSubview(NSTextField(labelWithString: "Quick-fill:"))
        nimRow.addArrangedSubview(nimCheck)
        nimRow.addArrangedSubview(oaiCheck)

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
            weak var typeSeg: NSSegmentedControl?
            weak var check: NSButton?
            weak var otherCheck: NSButton?
            @objc func handle() {
                guard let check = check else { return }
                if check.state == .on {
                    urlField?.stringValue = "https://integrate.api.nvidia.com/v1"
                    typeSeg?.selectedSegment = 1
                    otherCheck?.state = .off
                } else if urlField?.stringValue == "https://integrate.api.nvidia.com/v1" {
                    urlField?.stringValue = ""
                }
            }
        }
        let nimHandler = NimHandler()
        nimHandler.urlField = urlField
        nimHandler.typeSeg  = typeSeg
        nimHandler.check    = nimCheck
        objc_setAssociatedObject(nimCheck, "nimHandler", nimHandler, .OBJC_ASSOCIATION_RETAIN)
        nimCheck.target = nimHandler
        nimCheck.action = #selector(NimHandler.handle)

        class OAIHandler: NSObject {
            weak var urlField: NSTextField?
            weak var typeSeg: NSSegmentedControl?
            weak var check: NSButton?
            weak var otherCheck: NSButton?
            @objc func handle() {
                guard let check = check else { return }
                if check.state == .on {
                    urlField?.stringValue = "https://api.openai.com/v1"
                    typeSeg?.selectedSegment = 1
                    otherCheck?.state = .off
                } else if urlField?.stringValue == "https://api.openai.com/v1" {
                    urlField?.stringValue = ""
                }
            }
        }
        let oaiHandler = OAIHandler()
        oaiHandler.urlField    = urlField
        oaiHandler.typeSeg     = typeSeg
        oaiHandler.check       = oaiCheck
        oaiHandler.otherCheck  = nimCheck
        objc_setAssociatedObject(oaiCheck, "oaiHandler", oaiHandler, .OBJC_ASSOCIATION_RETAIN)
        oaiCheck.target = oaiHandler
        oaiCheck.action = #selector(OAIHandler.handle)

        nimHandler.otherCheck = oaiCheck

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

        // Test + models handler
        class BackendTestHandler: NSObject {
            weak var urlField: NSTextField?
            weak var keyField: NSSecureTextField?
            weak var typeSeg: NSSegmentedControl?
            weak var statusLbl: NSTextField?
            var modelPicker: PrivateDropdown?

            @objc func test() {
                guard let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                      let status = statusLbl else { return }
                let apiType = typeSeg?.selectedSegment ?? 0
                let apiKey  = keyField?.stringValue ?? ""
                status.textColor   = .secondaryLabelColor
                status.stringValue = "Testing…"
                let endpoint = apiType == 0 ? "\(url)/api/tags" : "\(url)/models"
                guard let reqURL = URL(string: endpoint) else {
                    status.stringValue = "✗ Invalid URL"; status.textColor = .systemRed; return
                }
                var req = URLRequest(url: reqURL, timeoutInterval: 5)
                if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
                URLSession.shared.dataTask(with: req) { _, response, error in
                    DispatchQueue.main.async {
                        if let e = error {
                            status.stringValue = "✗ \(e.localizedDescription)"; status.textColor = .systemRed
                        } else if let http = response as? HTTPURLResponse, http.statusCode < 300 {
                            status.stringValue = "✓ Connected"; status.textColor = .systemGreen
                        } else {
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                            status.stringValue = "✗ HTTP \(code)"; status.textColor = .systemRed
                        }
                    }
                }.resume()
            }

            @objc func refresh() {
                guard let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                      let picker = modelPicker else { return }
                let apiType = typeSeg?.selectedSegment ?? 0
                let apiKey  = keyField?.stringValue ?? ""
                picker.items = ["Loading…"]
                let endpoint = apiType == 0 ? "\(url)/api/tags" : "\(url)/models"
                guard let reqURL = URL(string: endpoint) else { picker.items = ["Invalid URL"]; return }
                var req = URLRequest(url: reqURL, timeoutInterval: 5)
                if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    var names: [String] = []
                    if let data = data {
                        if apiType == 0 {
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let models = json["models"] as? [[String: Any]] {
                                names = models.compactMap { $0["name"] as? String }
                            }
                        } else {
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let models = json["data"] as? [[String: Any]] {
                                names = models.compactMap { $0["id"] as? String }.sorted()
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        picker.items = names.isEmpty ? ["No models found"] : names
                        if picker.selected.isEmpty, let first = names.first { picker.selected = first }
                    }
                }.resume()
            }
        }

        // Test row
        let testRow = NSStackView()
        testRow.orientation = .horizontal
        testRow.spacing = 8
        let testBtn = NSButton(title: "Test", target: nil, action: nil)
        testBtn.bezelStyle = .rounded
        testBtn.font = NSFont.systemFont(ofSize: 11)
        let statusLbl = NSTextField(labelWithString: "")
        statusLbl.font = NSFont.systemFont(ofSize: 11)
        statusLbl.textColor = .secondaryLabelColor
        testRow.addArrangedSubview(testBtn)
        testRow.addArrangedSubview(statusLbl)

        // Models row — custom NSPanel dropdown (sharingType = .none, not visible in screen share)
        let modelPicker = PrivateDropdown()
        modelPicker.selected = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        modelPicker.onSelect = { model in
            UserDefaults.standard.set(model, forKey: "selectedModel")
        }
        let modelsRow = NSStackView()
        modelsRow.orientation = .horizontal
        modelsRow.spacing = 8
        let modelsLabel = NSTextField(labelWithString: "Model:")
        modelsLabel.frame.size.width = 70
        let refreshBtn = NSButton(title: "↺", target: nil, action: nil)
        refreshBtn.bezelStyle = .rounded
        refreshBtn.font = NSFont.systemFont(ofSize: 13)
        modelsRow.addArrangedSubview(modelsLabel)
        modelsRow.addArrangedSubview(modelPicker.button)
        modelsRow.addArrangedSubview(refreshBtn)
        objc_setAssociatedObject(stack, "modelPicker", modelPicker, .OBJC_ASSOCIATION_RETAIN)

        let testHandler = BackendTestHandler()
        testHandler.urlField   = urlField
        testHandler.keyField   = keyField
        testHandler.typeSeg    = typeSeg
        testHandler.statusLbl  = statusLbl
        testHandler.modelPicker = modelPicker
        objc_setAssociatedObject(stack, "testHandler", testHandler, .OBJC_ASSOCIATION_RETAIN)
        testBtn.target    = testHandler
        testBtn.action    = #selector(BackendTestHandler.test)
        refreshBtn.target = testHandler
        refreshBtn.action = #selector(BackendTestHandler.refresh)
        testHandler.refresh()

        // Hint
        let hint = NSTextField(labelWithString: "")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.stringValue = backenHint(typeSeg.selectedSegment)
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byWordWrapping
        hint.frame.size.width = 360

        let obs = typeSeg.observe(\.selectedSegment) { seg, _ in
            hint.stringValue = self.backenHint(seg.selectedSegment)
        }

        stack.addArrangedSubview(typeRow)
        stack.addArrangedSubview(nimRow)
        stack.addArrangedSubview(urlRow)
        stack.addArrangedSubview(keyRow)
        stack.addArrangedSubview(testRow)
        stack.addArrangedSubview(modelsRow)
        stack.addArrangedSubview(hint)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = urlField
        alert.window.sharingType = .none

        let result = alert.runModal()
        modelPicker.close()
        if result == .alertFirstButtonReturn {
            var newCfg = BackendConfig(
                type:   typeSeg.selectedSegment == 0 ? .ollama : .openai,
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
            : "OpenAI: https://api.openai.com/v1\nNIM: https://integrate.api.nvidia.com/v1\nllama.cpp: http://localhost:8080/v1\nLM Studio: http://localhost:1234/v1"
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// ── MovableWindow ─────────────────────────────────────────────────────────────

class MovableWindow: NSWindow {
    private var dragging = false
    private let headerHeight: CGFloat = 38

    override func sendEvent(_ event: NSEvent) {
        let h = contentView?.frame.height ?? frame.height
        let inHeader = event.locationInWindow.y >= h - headerHeight
        switch event.type {
        case .leftMouseDown:
            dragging = inHeader
        case .leftMouseUp:
            dragging = false
        case .leftMouseDragged where dragging:
            let o = frame.origin
            setFrameOrigin(NSPoint(x: o.x + event.deltaX, y: o.y - event.deltaY))
            return
        default: break
        }
        super.sendEvent(event)
    }
}

// ── ChatWindow ────────────────────────────────────────────────────────────────

class ChatWindow: NSObject, NSWindowDelegate {
    let window: MovableWindow
    let webView: WKWebViewWrapper

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 460, height: 620)
        window = MovableWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden    = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden     = true
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        window.sharingType = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let visualEffect = NSVisualEffectView(frame: frame)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active

        webView = WKWebViewWrapper(frame: visualEffect.bounds)
        webView.view.autoresizingMask = [.width, .height]
        visualEffect.addSubview(webView.view)
        window.contentView = visualEffect
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

// ── Screen capture ────────────────────────────────────────────────────────────

func captureScreenBase64(maxWidth: Int = 1440) -> String? {
    let cg = CGWindowListCreateImage(.infinite, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    if cg == nil {
        CGRequestScreenCaptureAccess()
        return nil
    }
    guard let cg = cg else { return nil }
    let w = cg.width, h = cg.height
    let scale = w > maxWidth ? Double(maxWidth) / Double(w) : 1.0
    let tw = max(1, Int(Double(w) * scale)), th = max(1, Int(Double(h) * scale))
    guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
    guard let resized = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: resized)
    guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png.base64EncodedString()
}

// ── WKWebViewWrapper ──────────────────────────────────────────────────────────

class WKWebViewWrapper: NSObject, WKScriptMessageHandler {
    let view: WKWebView
    let recorder = AudioRecorder()
    var isRecording = false
    var currentStreamSession: URLSession?
    var pendingScreenshot: String? = nil

    init(frame: NSRect = .zero) {
        let config = WKWebViewConfiguration()
        let cc = WKUserContentController()
        config.userContentController = cc
        view = WKWebView(frame: frame, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        super.init()
        for name in ["sendMessage","loadModels","startRecording","stopRecording","stopStream","checkWhisper","closeWindow","captureScreen","clearScreenshot","initModel"] {
            cc.add(self, name: name)
        }
        loadHTML()
        sendSavedModel()
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "sendMessage":
            guard let body = message.body as? [String: String],
                  let prompt = body["prompt"], let model = body["model"] else { return }
            let img = pendingScreenshot; pendingScreenshot = nil
            streamResponse(prompt: prompt, model: model, image: img)
        case "captureScreen":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                if let b64 = captureScreenBase64() {
                    self.pendingScreenshot = b64
                    DispatchQueue.main.async { self.view.evaluateJavaScript("onScreenshotCaptured()", completionHandler: nil) }
                } else {
                    DispatchQueue.main.async { self.view.evaluateJavaScript("onScreenshotError()", completionHandler: nil) }
                }
            }
        case "clearScreenshot":
            pendingScreenshot = nil
        case "initModel":
            sendSavedModel()
        case "loadModels":   fetchModels()
        case "checkWhisper": checkWhisperInstall()
        case "startRecording":
            guard !isRecording else { return }
            requestMicAndRecord()
        case "closeWindow":
            DispatchQueue.main.async { self.view.window?.performClose(nil) }
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

    func sendSavedModel() {
        if let saved = UserDefaults.standard.string(forKey: "selectedModel") {
            view.evaluateJavaScript("setSavedModel('\(saved)')", completionHandler: nil)
        }
    }

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

    func streamResponse(prompt: String, model: String, image: String? = nil) {
        let cfg = BackendConfig.current
        switch cfg.type {
        case .ollama: streamOllama(prompt: prompt, model: model, cfg: cfg, image: image)
        case .openai: streamOpenAI(prompt: prompt, model: model, cfg: cfg, image: image)
        }
    }

    func streamOllama(prompt: String, model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/api/generate") else { return }
        var body: [String: Any] = ["model": model, "prompt": prompt, "stream": true]
        if let img = image { body["images"] = [img] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        startStream(req: req, parser: OllamaStreamParser())
    }

    func streamOpenAI(prompt: String, model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/chat/completions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        let content: Any
        if let img = image {
            content = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"]]
            ]
        } else {
            content = prompt
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "stream": true,
            "messages": [["role": "user", "content": content]]
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
  --bg:rgba(28,30,36,0.55);--surface:rgba(41,44,51,0.7);--border:rgba(255,255,255,0.08);
  --text:#d1d1d6;--muted:#6b6b7a;--accent:#4ade80;
  --user:#7dd3fc;--error:#f87171;--rec:#f87171;
  --font:'JetBrains Mono','Menlo',monospace;
}
html,body{height:100%;background:transparent;color:var(--text);
  font-family:var(--font);font-size:12.5px;line-height:1.6;
  overflow:hidden;-webkit-font-smoothing:antialiased}
#app{background:var(--bg);border-radius:12px;display:flex;flex-direction:column;height:100vh;overflow:hidden}
#header{display:flex;align-items:center;justify-content:space-between;
  padding:9px 14px;border-bottom:1px solid var(--border);
  background:var(--surface);-webkit-app-region:drag;
  user-select:none;-webkit-user-select:none;cursor:default;flex-shrink:0}
#header *{user-select:none;-webkit-user-select:none}
#dot{width:6px;height:6px;border-radius:50%;background:var(--accent);
  box-shadow:0 0 5px var(--accent);animation:pulse 2.5s ease-in-out infinite;
  pointer-events:none}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.35}}
#header-left{display:flex;align-items:center;gap:8px}
#backend-badge{font-size:9px;letter-spacing:.06em;text-transform:uppercase;
  color:var(--muted);padding:1px 5px;border:1px solid var(--border);border-radius:3px;
  pointer-events:none}
#autoscroll-btn{-webkit-appearance:none;appearance:none;background:none;
  border:1px solid var(--border);color:var(--muted);
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
  background:var(--surface);border:1px solid var(--border);border-radius:6px;
  min-width:220px;z-index:999;overflow-y:auto;max-height:calc(100vh - 60px);
  box-shadow:0 8px 24px rgba(0,0,0,.15)}
#model-dropdown.open{display:block}
.model-opt{padding:8px 14px;font-size:11.5px;cursor:pointer;color:var(--text);
  font-family:var(--font);transition:background .1s;white-space:nowrap}
.model-opt:hover{background:var(--border)}
.model-opt.active{color:var(--accent)}
#msgs{flex:1;overflow-y:auto;padding:14px;scroll-behavior:smooth}
#msgs::-webkit-scrollbar{width:3px}
#msgs::-webkit-scrollbar-thumb{background:var(--border);border-radius:2px}
.msg{margin-bottom:16px;animation:fadein .15s ease;background:var(--surface);padding:12px;border-radius:8px;border:1px solid var(--border);transition:all 0.3s;}
.msg.user{background:transparent;border-color:transparent;padding:4px 0px;}
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
#screenshot-btn{padding:5px 8px;line-height:0;font-size:13px}
#screenshot-btn.captured{border-color:var(--accent);color:var(--accent)}
#screenshot-indicator{display:none;font-size:10px;color:var(--accent);padding:3px 14px 0;
  letter-spacing:.03em;cursor:pointer}
#screenshot-indicator:hover{color:var(--error)}
#hint{font-size:10px;color:var(--muted);padding:4px 14px 0;display:none;letter-spacing:.03em}
#hint.visible{display:block}
#close-btn{-webkit-appearance:none;appearance:none;background:none;border:none;
  color:var(--muted);font-size:16px;line-height:1;
  cursor:pointer;padding:0 4px;transition:color .15s;-webkit-app-region:no-drag}
#close-btn:hover{color:var(--error)}
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
    <div style="display:flex;align-items:center;gap:4px;-webkit-app-region:no-drag">
      <button id="autoscroll-btn" title="Auto-scroll">↓</button>
      <button id="close-btn" title="Close">×</button>
    </div>
  </div>
  <div id="msgs"></div>
  <div id="hint"></div>
  <div id="screenshot-indicator" title="Screenshot attached — click to remove">📎 screenshot attached</div>
  <div id="bottom">
    <textarea id="inp" placeholder="Message… (Enter to send)" rows="1"></textarea>
    <button id="screenshot-btn" class="action-btn" title="Capture screen"><svg width="16" height="14" viewBox="0 0 16 14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="square"><path d="M1 4V1h4M11 1h4v3M15 10v3h-4M5 13H1v-3"/></svg></button>
    <button id="mic-btn" class="action-btn" title="Click to record">🎙</button>
    <button id="btn" class="action-btn">↵</button>
  </div>
</div>
<script>
let model = '', busy = false, currentBody = null;
let micState = 'idle', streaming = false;
let autoScroll = true;
let hasScreenshot = false;

function setSavedModel(m) { window.savedModel = m; }

window.webkit.messageHandlers.loadModels.postMessage({});
window.webkit.messageHandlers.checkWhisper.postMessage({});
window.webkit.messageHandlers.initModel.postMessage({});

// ── Model dropdown ────────────────────────────────────────────────────────────
const modelBtn      = document.getElementById('model-btn');
const modelName     = document.getElementById('model-name');
const modelDropdown = document.getElementById('model-dropdown');
const backendBadge  = document.getElementById('backend-badge');

modelBtn.addEventListener('click', e => { e.stopPropagation(); modelDropdown.classList.toggle('open'); });
document.addEventListener('click', () => modelDropdown.classList.remove('open'));

document.getElementById('close-btn').addEventListener('click', () => {
  window.webkit.messageHandlers.closeWindow.postMessage({});
});

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
  const saved = window.savedModel; window.savedModel = null;
  if (saved) {
    const match = models.find(m => m === saved || m.startsWith(saved.split(':')[0]));
    if (match) model = match;
  }
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

// ── Screenshot ────────────────────────────────────────────────────────────────
const screenshotBtn = document.getElementById('screenshot-btn');
const screenshotIndicator = document.getElementById('screenshot-indicator');
const SCREENSHOT_ICON = screenshotBtn.innerHTML;

screenshotBtn.addEventListener('click', e => {
  e.preventDefault();
  if (hasScreenshot) {
    clearScreenshotUI();
    window.webkit.messageHandlers.clearScreenshot.postMessage({});
  } else {
    screenshotBtn.innerHTML = '⏳';
    screenshotBtn.disabled = true;
    window.webkit.messageHandlers.captureScreen.postMessage({});
  }
});

screenshotIndicator.addEventListener('click', () => {
  clearScreenshotUI();
  window.webkit.messageHandlers.clearScreenshot.postMessage({});
});

function clearScreenshotUI() {
  hasScreenshot = false;
  screenshotBtn.innerHTML = SCREENSHOT_ICON;
  screenshotBtn.classList.remove('captured');
  screenshotBtn.title = 'Capture screen';
  screenshotBtn.disabled = false;
  screenshotIndicator.style.display = 'none';
}

function onScreenshotCaptured() {
  hasScreenshot = true;
  screenshotBtn.innerHTML = SCREENSHOT_ICON;
  screenshotBtn.classList.add('captured');
  screenshotBtn.title = 'Screenshot attached — click to remove';
  screenshotBtn.disabled = false;
  screenshotIndicator.style.display = 'block';
}

function onScreenshotError() {
  screenshotBtn.innerHTML = SCREENSHOT_ICON;
  screenshotBtn.disabled = false;
  screenshotBtn.title = 'Screen capture failed — check System Settings > Privacy > Screen Recording';
}

function sendText(text) {
  if (busy || !text) return;
  modelDropdown.classList.remove('open');
  addMsg('user').textContent = text + (hasScreenshot ? ' 📎' : '');
  currentBody = addMsg('ai');
  currentBody.classList.add('cursor');
  busy = true; streaming = true;
  btn.textContent = '⏹'; btn.classList.add('stopping');
  if (hasScreenshot) clearScreenshotUI();
  window.webkit.messageHandlers.sendMessage.postMessage({prompt: text, model: model});
}

function send() {
  const inp = document.getElementById('inp');
  let text = inp.value.trim();
  if (!text && hasScreenshot) text = 'Look at this screenshot. Find any programming problem, error, or bug and explain how to fix it.';
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