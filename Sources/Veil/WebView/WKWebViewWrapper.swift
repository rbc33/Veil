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
