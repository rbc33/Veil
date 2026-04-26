import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?
    var globalHotKey: GlobalHotKey?

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
        globalHotKey = GlobalHotKey { [weak self] in self?.hotKeyToggleChat() }
    }

    func hotKeyToggleChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        if chatWindow?.window.isVisible == true {
            chatWindow?.window.orderOut(nil)
        } else {
            chatWindow?.showAndFocus()
        }
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

        let screenW = NSScreen.main?.frame.width ?? 1440
        let pad: CGFloat = 20
        let panelW  = (screenW - 200) * 0.54
        let fieldW  = panelW - 2 * pad - 90

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.center()
        panel.sharingType = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(red: 41/255, green: 44/255, blue: 51/255, alpha: 1)
        panel.alphaValue = 0.9
        panel.isOpaque = false

        struct Preset {
            let label: String
            let type:  BackendType
            let url:   String
            let hint:  String
        }
        let presets: [Preset] = [
            Preset(label: "Ollama",        type: .ollama,     url: "http://localhost:11434",              hint: "Local Ollama instance"),
            Preset(label: "OpenAI",        type: .openai,     url: "https://api.openai.com/v1",           hint: "Requires API key"),
            Preset(label: "Anthropic",     type: .anthropic,  url: "https://api.anthropic.com/v1",        hint: "Requires API key"),
            Preset(label: "OpenRouter",    type: .openrouter, url: "https://openrouter.ai/api/v1",        hint: "Requires API key"),
            Preset(label: "Azure OpenAI",  type: .azure,      url: "",                                    hint: "Enter your Azure endpoint"),
            Preset(label: "NVIDIA NIM",    type: .openai,     url: "https://integrate.api.nvidia.com/v1", hint: "Requires API key"),
            Preset(label: "llama.cpp",     type: .openai,     url: "http://localhost:8080/v1",            hint: "Local llama.cpp server"),
            Preset(label: "LM Studio",     type: .openai,     url: "http://localhost:1234/v1",            hint: "Local LM Studio server"),
        ]

        let selectedIdx = presets.firstIndex(where: { $0.url == cfg.url && $0.type == cfg.type })
                       ?? presets.firstIndex(where: { $0.type == cfg.type })
                       ?? 0

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 9

        let backendRow = NSStackView()
        backendRow.orientation = .horizontal
        backendRow.spacing = 8
        let backendLabel = NSTextField(labelWithString: "Backend:")
        backendLabel.frame.size.width = 70
        let backendPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        backendPopup.addItems(withTitles: presets.map(\.label))
        backendPopup.selectItem(at: selectedIdx)
        backendRow.addArrangedSubview(backendLabel)
        backendRow.addArrangedSubview(backendPopup)

        let urlRow = NSStackView()
        urlRow.orientation = .horizontal
        urlRow.spacing = 8
        let urlLabel = NSTextField(labelWithString: "URL:")
        urlLabel.frame.size.width = 70
        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: fieldW, height: 24))
        urlField.stringValue = cfg.url
        urlField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.placeholderString = "http://localhost:11434"
        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        urlRow.addArrangedSubview(urlLabel)
        urlRow.addArrangedSubview(urlField)

        let hint = NSTextField(labelWithString: presets[selectedIdx].hint)
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.maximumNumberOfLines = 1

        class BackendPopupHandler: NSObject {
            weak var urlField: NSTextField?
            weak var hintField: NSTextField?
            weak var backendPopup: NSPopUpButton?
            var presets: [Preset] = []
            @objc func handle() {
                let idx = backendPopup?.indexOfSelectedItem ?? 0
                guard idx < presets.count else { return }
                let p = presets[idx]
                if !p.url.isEmpty { urlField?.stringValue = p.url }
                hintField?.stringValue = p.hint
            }
        }
        let bpHandler = BackendPopupHandler()
        bpHandler.urlField     = urlField
        bpHandler.hintField    = hint
        bpHandler.backendPopup = backendPopup
        bpHandler.presets      = presets
        objc_setAssociatedObject(backendPopup, "bpHandler", bpHandler, .OBJC_ASSOCIATION_RETAIN)
        backendPopup.target = bpHandler
        backendPopup.action = #selector(BackendPopupHandler.handle)

        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.spacing = 8
        let keyLabel = NSTextField(labelWithString: "API key:")
        keyLabel.frame.size.width = 70
        let keyField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: fieldW, height: 24))
        keyField.stringValue = cfg.apiKey
        keyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.placeholderString = "Optional"
        keyRow.addArrangedSubview(keyLabel)
        keyRow.addArrangedSubview(keyField)

        class BackendTestHandler: NSObject {
            weak var urlField: NSTextField?
            weak var keyField: NSSecureTextField?
            weak var backendPopup: NSPopUpButton?
            weak var statusLbl: NSTextField?
            var modelPicker: PrivateDropdown?
            var presets: [Preset] = []

            var currentType: BackendType {
                let idx = backendPopup?.indexOfSelectedItem ?? 0
                return idx < presets.count ? presets[idx].type : .ollama
            }

            @objc func test() {
                guard let url = urlField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                      let status = statusLbl else { return }
                let isOllama = currentType == .ollama
                let apiKey   = keyField?.stringValue ?? ""
                status.textColor   = .secondaryLabelColor
                status.stringValue = "Testing…"
                let endpoint = isOllama ? "\(url)/api/tags" : "\(url)/models"
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
                let isOllama = currentType == .ollama
                let apiKey   = keyField?.stringValue ?? ""
                picker.items = ["Loading…"]
                let endpoint = isOllama ? "\(url)/api/tags" : "\(url)/models"
                guard let reqURL = URL(string: endpoint) else { picker.items = ["Invalid URL"]; return }
                var req = URLRequest(url: reqURL, timeoutInterval: 5)
                if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    var names: [String] = []
                    if let data = data {
                        if isOllama {
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
        modelPicker.onSelect = { model in UserDefaults.standard.set(model, forKey: "selectedModel") }
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
        testHandler.urlField     = urlField
        testHandler.keyField     = keyField
        testHandler.backendPopup = backendPopup
        testHandler.statusLbl    = statusLbl
        testHandler.modelPicker  = modelPicker
        testHandler.presets      = presets
        objc_setAssociatedObject(stack, "testHandler", testHandler, .OBJC_ASSOCIATION_RETAIN)
        testBtn.target    = testHandler
        testBtn.action    = #selector(BackendTestHandler.test)
        refreshBtn.target = testHandler
        refreshBtn.action = #selector(BackendTestHandler.refresh)
        testHandler.refresh()

        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal
        shortcutRow.spacing = 8
        let shortcutLabel = NSTextField(labelWithString: "Shortcut:")
        shortcutLabel.frame.size.width = 70
        let recorder = ShortcutRecorder(storagePrefix: "shortcut", defaultShortcut: .default)
        recorder.onChange = { [weak self] _ in self?.chatWindow?.webView.sendShortcut() }
        let shortcutHint = NSTextField(labelWithString: "mic  ·  click to record  ·  ↩ = modifier-only  ·  Esc = cancel")
        shortcutHint.font = NSFont.systemFont(ofSize: 10)
        shortcutHint.textColor = .secondaryLabelColor
        shortcutRow.addArrangedSubview(shortcutLabel)
        shortcutRow.addArrangedSubview(recorder.field)
        shortcutRow.addArrangedSubview(shortcutHint)
        objc_setAssociatedObject(stack, "recorder", recorder, .OBJC_ASSOCIATION_RETAIN)

        let toggleRow = NSStackView()
        toggleRow.orientation = .horizontal
        toggleRow.spacing = 8
        let toggleLabel = NSTextField(labelWithString: "Toggle:")
        toggleLabel.frame.size.width = 70
        let toggleRecorder = ShortcutRecorder(storagePrefix: "toggleShortcut", defaultShortcut: .defaultToggle)
        toggleRecorder.onChange = { [weak self] s in self?.globalHotKey?.register(s) }
        let toggleHint = NSTextField(labelWithString: "show/hide window  ·  key required  ·  Esc = cancel")
        toggleHint.font = NSFont.systemFont(ofSize: 10)
        toggleHint.textColor = .secondaryLabelColor
        toggleRow.addArrangedSubview(toggleLabel)
        toggleRow.addArrangedSubview(toggleRecorder.field)
        toggleRow.addArrangedSubview(toggleHint)
        objc_setAssociatedObject(stack, "toggleRecorder", toggleRecorder, .OBJC_ASSOCIATION_RETAIN)

        let captureRow = NSStackView()
        captureRow.orientation = .horizontal
        captureRow.spacing = 8
        let captureLabel = NSTextField(labelWithString: "Capture:")
        captureLabel.frame.size.width = 70
        let captureRecorder = ShortcutRecorder(storagePrefix: "captureShortcut", defaultShortcut: .defaultCapture)
        captureRecorder.onChange = { [weak self] _ in self?.chatWindow?.webView.sendCaptureShortcut() }
        let captureHint = NSTextField(labelWithString: "screenshot  ·  click to record  ·  Esc = cancel")
        captureHint.font = NSFont.systemFont(ofSize: 10)
        captureHint.textColor = .secondaryLabelColor
        captureRow.addArrangedSubview(captureLabel)
        captureRow.addArrangedSubview(captureRecorder.field)
        captureRow.addArrangedSubview(captureHint)
        objc_setAssociatedObject(stack, "captureRecorder", captureRecorder, .OBJC_ASSOCIATION_RETAIN)

        let sysLabel = NSTextField(labelWithString: "System prompt:")
        sysLabel.font = NSFont.systemFont(ofSize: 11)
        let sysTextView = NSTextView()
        sysTextView.isEditable = true
        sysTextView.isRichText = false
        sysTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sysTextView.string = UserDefaults.standard.string(forKey: "systemPrompt") ?? ""
        sysTextView.textContainerInset = NSSize(width: 4, height: 4)
        sysTextView.backgroundColor = NSColor(red: 30/255, green: 32/255, blue: 38/255, alpha: 1)
        let sysScroll = NSScrollView()
        sysScroll.documentView = sysTextView
        sysScroll.hasVerticalScroller = true
        sysScroll.autohidesScrollers = true
        sysScroll.borderType = .lineBorder
        sysScroll.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        sysScroll.wantsLayer = true
        sysScroll.heightAnchor.constraint(equalToConstant: 44).isActive = true
        sysScroll.widthAnchor.constraint(equalToConstant: (panelW - 2 * pad) * 0.9).isActive = true

        let sysRow = NSStackView()
        sysRow.orientation = .vertical
        sysRow.alignment = .leading
        sysRow.spacing = 3
        sysRow.addArrangedSubview(sysLabel)
        sysRow.addArrangedSubview(sysScroll)

        stack.addArrangedSubview(backendRow)
        stack.addArrangedSubview(urlRow)
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(keyRow)
        stack.addArrangedSubview(testRow)
        stack.addArrangedSubview(modelsRow)
        stack.addArrangedSubview(shortcutRow)
        stack.addArrangedSubview(captureRow)
        stack.addArrangedSubview(toggleRow)
        stack.addArrangedSubview(sysRow)
        stack.setCustomSpacing(2, after: sysRow)

        var saved = false
        let saveBtn   = NSButton(title: "Save",   target: nil, action: nil)
        let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
        saveBtn.bezelStyle   = .rounded
        cancelBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent   = "\r"
        cancelBtn.keyEquivalent = "\u{1b}"

        class BtnHandler: NSObject {
            var onSave: (() -> Void)?
            var onCancel: (() -> Void)?
            @objc func save()   { onSave?()   }
            @objc func cancel() { onCancel?() }
        }
        let btnHandler = BtnHandler()
        btnHandler.onSave   = { saved = true;  NSApp.stopModal() }
        btnHandler.onCancel = { saved = false; NSApp.stopModal() }
        saveBtn.target   = btnHandler; saveBtn.action   = #selector(BtnHandler.save)
        cancelBtn.target = btnHandler; cancelBtn.action = #selector(BtnHandler.cancel)

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        btnRow.addArrangedSubview(NSView())
        btnRow.addArrangedSubview(cancelBtn)
        btnRow.addArrangedSubview(saveBtn)

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        if let cv = panel.contentView {
            cv.wantsLayer = true
            cv.layer?.backgroundColor = NSColor(red: 41/255, green: 44/255, blue: 51/255, alpha: 1).cgColor
            cv.addSubview(iconView)
            cv.addSubview(stack)
            cv.addSubview(btnRow)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
                iconView.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),

                stack.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
                stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
                stack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

                btnRow.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
                btnRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
                btnRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
                btnRow.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
            ])
        }

        objc_setAssociatedObject(panel, "btnHandler", btnHandler, .OBJC_ASSOCIATION_RETAIN)
        panel.initialFirstResponder = urlField

        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        modelPicker.close()

        if saved {
            let idx = backendPopup.indexOfSelectedItem
            let preset = idx < presets.count ? presets[idx] : presets[0]
            var newCfg = BackendConfig(
                type:   preset.type,
                url:    urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if newCfg.url.isEmpty { newCfg.url = preset.url }
            BackendConfig.current = newCfg
            let sysPrompt = sysTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(sysPrompt.isEmpty ? nil : sysPrompt, forKey: "systemPrompt")
            chatWindow?.webView.fetchModels()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}
