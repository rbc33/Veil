import WebKit
import AVFoundation

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
            guard let body = message.body as? [String: Any],
                  let messages = body["messages"] as? [[String: Any]],
                  let model = body["model"] as? String else { return }
            let img = (body["screenshot"] as? String) ?? pendingScreenshot
            pendingScreenshot = nil
            streamResponse(messages: messages, model: model, image: img)
        case "captureScreen":
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                if let b64 = captureScreenBase64() {
                    self.pendingScreenshot = b64
                    DispatchQueue.main.async { self.view.evaluateJavaScript("onScreenshotCaptured('\(b64)')", completionHandler: nil) }
                } else {
                    DispatchQueue.main.async { self.view.evaluateJavaScript("onScreenshotError()", completionHandler: nil) }
                }
            }
        case "clearScreenshot":
            pendingScreenshot = nil
        case "initModel":
            sendSavedModel()
            sendShortcut()
            sendCaptureShortcut()
        case "loadModels":   fetchModels()
        case "checkWhisper": checkWhisperInstall()
        case "startRecording":
            guard !isRecording else { return }
            requestMicAndRecord()
        case "closeWindow":
            DispatchQueue.main.async { self.view.window?.orderOut(nil) }
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

    func sendSavedModel() {
        if let saved = UserDefaults.standard.string(forKey: "selectedModel") {
            view.evaluateJavaScript("setSavedModel('\(saved)')", completionHandler: nil)
        }
    }

    func sendShortcut() {
        view.evaluateJavaScript("setShortcut(\(RecordingShortcut.current.jsJSON))", completionHandler: nil)
    }

    func sendCaptureShortcut() {
        view.evaluateJavaScript("setCaptureShortcut(\(RecordingShortcut.capture.jsJSON))", completionHandler: nil)
    }

    func fetchModels() {
        let cfg = BackendConfig.current
        switch cfg.type {
        case .ollama:      fetchOllamaModels(cfg: cfg)
        case .openai:      fetchOpenAIModels(cfg: cfg)
        case .anthropic:   fetchAnthropicModels(cfg: cfg)
        case .openrouter:  fetchOpenAIModels(cfg: cfg)
        case .azure:       fetchOpenAIModels(cfg: cfg)
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

    func fetchAnthropicModels(cfg: BackendConfig) {
        let base = cfg.url.isEmpty ? "https://api.anthropic.com/v1" : cfg.url
        guard let url = URL(string: "\(base)/models") else { return }
        var req = URLRequest(url: url)
        req.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

    func streamResponse(messages: [[String: Any]], model: String, image: String? = nil) {
        let cfg = BackendConfig.current
        var msgs = messages
        if let sp = UserDefaults.standard.string(forKey: "systemPrompt"), !sp.isEmpty {
            msgs.insert(["role": "system", "content": sp], at: 0)
        }
        switch cfg.type {
        case .ollama:     streamOllama(messages: msgs, model: model, cfg: cfg, image: image)
        case .openai:     streamOpenAI(messages: msgs, model: model, cfg: cfg, image: image)
        case .anthropic:  streamAnthropic(messages: msgs, model: model, cfg: cfg, image: image)
        case .openrouter: streamOpenAI(messages: msgs, model: model, cfg: cfg, image: image)
        case .azure:      streamAzure(messages: msgs, model: model, cfg: cfg, image: image)
        }
    }

    func streamOllama(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/api/chat") else { return }
        var msgs = messages
        if let img = image, !msgs.isEmpty {
            var last = msgs[msgs.count - 1]
            last["images"] = [img]
            msgs[msgs.count - 1] = last
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "stream": true])
        startStream(req: req, parser: OllamaStreamParser())
    }

    func streamOpenAI(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/chat/completions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.apiKey.isEmpty { req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization") }
        var msgs = messages
        if let img = image, !msgs.isEmpty {
            var last = msgs[msgs.count - 1]
            if let text = last["content"] as? String {
                last["content"] = [
                    ["type": "text", "text": text],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"]]
                ]
                msgs[msgs.count - 1] = last
            }
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "stream": true, "messages": msgs])
        startStream(req: req, parser: OpenAIStreamParser())
    }

    func streamAzure(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        guard let url = URL(string: "\(cfg.url)/chat/completions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.apiKey.isEmpty { req.setValue(cfg.apiKey, forHTTPHeaderField: "api-key") }
        var msgs = messages
        if let img = image, !msgs.isEmpty {
            var last = msgs[msgs.count - 1]
            if let text = last["content"] as? String {
                last["content"] = [
                    ["type": "text", "text": text],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"]]
                ]
                msgs[msgs.count - 1] = last
            }
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "stream": true, "messages": msgs])
        startStream(req: req, parser: OpenAIStreamParser())
    }

    func streamAnthropic(messages: [[String: Any]], model: String, cfg: BackendConfig, image: String? = nil) {
        let base = cfg.url.isEmpty ? "https://api.anthropic.com/v1" : cfg.url
        guard let url = URL(string: "\(base)/messages") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cfg.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var userMsgs = messages.filter { ($0["role"] as? String) != "system" }
        let systemText = messages.first(where: { ($0["role"] as? String) == "system" })?["content"] as? String

        if let img = image, !userMsgs.isEmpty {
            var last = userMsgs[userMsgs.count - 1]
            if let text = last["content"] as? String {
                last["content"] = [
                    ["type": "text", "text": text],
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": img]]
                ]
                userMsgs[userMsgs.count - 1] = last
            }
        }

        var body: [String: Any] = ["model": model, "max_tokens": 8096, "stream": true, "messages": userMsgs]
        if let sys = systemText, !sys.isEmpty { body["system"] = sys }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        startStream(req: req, parser: AnthropicStreamParser())
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
