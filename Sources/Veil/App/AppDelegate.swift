import AppKit

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
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(configureBackend), keyEquivalent: ""))
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
        alert.messageText = "Settings"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 360, height: 290))
        stack.orientation = .vertical
        stack.alignment   = .left
        stack.spacing     = 10

        let typeRow = NSStackView()
        typeRow.orientation = .horizontal
        typeRow.spacing = 8
        let typeLabel = NSTextField(labelWithString: "Backend:")
        typeLabel.frame.size.width = 70
        let typeSeg = NSSegmentedControl(labels: ["Ollama", "OpenAI-compatible"], trackingMode: .selectOne, target: nil, action: nil)
        typeSeg.selectedSegment = cfg.type == .ollama ? 0 : 1
        typeRow.addArrangedSubview(typeLabel)
        typeRow.addArrangedSubview(typeSeg)

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
        testHandler.urlField    = urlField
        testHandler.keyField    = keyField
        testHandler.typeSeg     = typeSeg
        testHandler.statusLbl   = statusLbl
        testHandler.modelPicker = modelPicker
        objc_setAssociatedObject(stack, "testHandler", testHandler, .OBJC_ASSOCIATION_RETAIN)
        testBtn.target    = testHandler
        testBtn.action    = #selector(BackendTestHandler.test)
        refreshBtn.target = testHandler
        refreshBtn.action = #selector(BackendTestHandler.refresh)
        testHandler.refresh()

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

        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8
        let shortcutLabel = NSTextField(labelWithString: "Shortcut:")
        shortcutLabel.frame.size.width = 70
        let recorder = ShortcutRecorder()
        recorder.onChange = { [weak self] _ in self?.chatWindow?.webView.sendShortcut() }
        let shortcutHint = NSTextField(labelWithString: "click to record  ·  ↩ = modifier-only  ·  Esc = cancel")
        shortcutHint.font = NSFont.systemFont(ofSize: 10)
        shortcutHint.textColor = .secondaryLabelColor
        shortcutRow.addArrangedSubview(shortcutLabel)
        shortcutRow.addArrangedSubview(recorder.field)
        shortcutRow.addArrangedSubview(shortcutHint)
        objc_setAssociatedObject(stack, "recorder", recorder, .OBJC_ASSOCIATION_RETAIN)

        stack.addArrangedSubview(typeRow)
        stack.addArrangedSubview(nimRow)
        stack.addArrangedSubview(urlRow)
        stack.addArrangedSubview(keyRow)
        stack.addArrangedSubview(testRow)
        stack.addArrangedSubview(modelsRow)
        stack.addArrangedSubview(shortcutRow)
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
