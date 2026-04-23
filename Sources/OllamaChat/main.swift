import AppKit
import Foundation
import AVFoundation

// ── Constantes ────────────────────────────────────────────────────────────────

let WHISPER_BIN   = "/usr/local/bin/whisper-cli"   // brew install whisper-cpp
let WHISPER_MODEL = NSHomeDirectory() + "/.ollama-chat/ggml-base.bin"

// URL de Ollama — se guarda en UserDefaults para persistir entre sesiones
var OLLAMA_BASE: String {
    get { UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434" }
    set { UserDefaults.standard.set(newValue, forKey: "ollamaURL") }
}

// ── AppDelegate ───────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "⬡"
            button.action = #selector(toggleChat)
            button.target = self
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Abrir chat", action: #selector(toggleChat), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Cambiar URL de Ollama…", action: #selector(changeURL), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu

        // Crear carpeta de datos y descargar modelo whisper si hace falta
        setupWhisper()
    }

    @objc func toggleChat() {
        if chatWindow == nil { chatWindow = ChatWindow() }
        chatWindow?.showAndFocus()
    }

    @objc func changeURL() {
        let alert = NSAlert()
        alert.messageText = "URL de Ollama"
        alert.informativeText = "Introduce la URL del servidor Ollama:"
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = OLLAMA_BASE
        input.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = input

        alert.window.initialFirstResponder = input

        if alert.runModal() == .alertFirstButtonReturn {
            let url = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                OLLAMA_BASE = url
                // Recargar modelos en la ventana abierta
                chatWindow?.webView.fetchModels()
            }
        }
    }

    @objc func quit() { NSApp.terminate(nil) }

    func setupWhisper() {
        let dir = NSHomeDirectory() + "/.ollama-chat"
        try? FileManager.default.createDirectory(atPath: dir,
            withIntermediateDirectories: true)
        // El modelo se descarga la primera vez que se usa el micrófono
    }
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

class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var session: AVCaptureSession?
    private var audioFile: AVAudioFile?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
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

        // Archivo WAV 16kHz mono (lo que espera whisper)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: tmpURL, settings: settings)
        } catch {
            print("[audio] error creando archivo: \(error)")
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            // Convertir a 16kHz mono si hace falta
            if let converted = self.convert(buffer: buffer, to: file.processingFormat) {
                try? file.write(from: converted)
            } else {
                try? file.write(from: buffer)
            }
        }

        do {
            try engine.start()
        } catch {
            print("[audio] engine start error: \(error)")
        }
    }

    func stop() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil  // flush
        onDone?(outputURL)
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != format,
              let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return nil
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var inputDone = false
        converter.convert(to: out, error: &error) { _, status in
            if inputDone {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            inputDone = true
            return buffer
        }
        return error == nil ? out : nil
    }
}

// ── Whisper transcription ─────────────────────────────────────────────────────

func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
    // Verificar que whisper-cli existe
    guard FileManager.default.fileExists(atPath: WHISPER_BIN) else {
        // Intentar ruta alternativa de Homebrew arm64
        let altBin = "/opt/homebrew/bin/whisper-cli"
        if FileManager.default.fileExists(atPath: altBin) {
            transcribeWith(bin: altBin, audioURL: audioURL, completion: completion)
            return
        }
        completion(nil)
        return
    }
    transcribeWith(bin: WHISPER_BIN, audioURL: audioURL, completion: completion)
}

func findWhisperModel() -> String? {
    // Buscar en las ubicaciones estándar de whisper-cpp (Homebrew)
    let candidates = [
        "/opt/homebrew/share/whisper-cpp",
        "/opt/homebrew/share/whisper-cpp/models",
        "/usr/local/share/whisper-cpp",
        "/usr/local/share/whisper-cpp/models",
        NSHomeDirectory() + "/.cache/whisper",
        NSHomeDirectory() + "/.ollama-chat",
    ]
    let preferred = ["ggml-base.en.bin", "ggml-base.bin", "ggml-small.bin",
                     "ggml-tiny.bin", "ggml-medium.bin", "ggml-large.bin"]
    for dir in candidates {
        // Primero buscar modelos en orden de preferencia
        for name in preferred {
            let path = dir + "/" + name
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Luego cualquier ggml
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            if let m = files.first(where: { $0.hasSuffix(".bin") && $0.contains("ggml") }) {
                return dir + "/" + m
            }
        }
    }
    return nil
}

func transcribeWith(bin: String, audioURL: URL, completion: @escaping (String?) -> Void) {
    guard let modelPath = findWhisperModel() else {
        print("[whisper] no model found")
        completion(nil)
        return
    }
    print("[whisper] using model: \(modelPath)")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: bin)
    task.arguments = [
        "--model", modelPath,
        "--language", "auto",
        "--output-txt",
        "--no-prints",
        "--file", audioURL.path
    ]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    task.terminationHandler = { _ in
        // whisper-cli escribe el resultado en archivo .txt junto al audio
        let txtURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
        if let text = try? String(contentsOf: txtURL, encoding: .utf8) {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: txtURL)
            try? FileManager.default.removeItem(at: audioURL)
            completion(cleaned.isEmpty ? nil : cleaned)
        } else {
            // Intentar leer stdout
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? FileManager.default.removeItem(at: audioURL)
            completion(text.isEmpty ? nil : text)
        }
    }

    do {
        try task.run()
    } catch {
        print("[whisper] error: \(error)")
        completion(nil)
    }
}

// ── WKWebView wrapper ─────────────────────────────────────────────────────────

import WebKit

class WKWebViewWrapper: NSObject, WKScriptMessageHandler {
    let view: WKWebView
    let recorder = AudioRecorder()
    var isRecording = false
    var currentStreamSession: URLSession?

    init(frame: NSRect = .zero) {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        view = WKWebView(frame: frame, configuration: config)
        view.setValue(false, forKey: "drawsBackground")

        super.init()

        contentController.add(self, name: "sendMessage")
        contentController.add(self, name: "loadModels")
        contentController.add(self, name: "startRecording")
        contentController.add(self, name: "stopRecording")
        contentController.add(self, name: "stopStream")
        contentController.add(self, name: "checkWhisper")

        loadHTML()
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        switch message.name {
        case "sendMessage":
            guard let body = message.body as? [String: String],
                  let prompt = body["prompt"], let model = body["model"] else { return }
            streamResponse(prompt: prompt, model: model)

        case "loadModels":
            fetchModels()

        case "checkWhisper":
            checkWhisperInstall()

        case "startRecording":
            guard !isRecording else { return }
            requestMicAndRecord()

        case "stopStream":
            currentStreamSession?.invalidateAndCancel()
            currentStreamSession = nil
            DispatchQueue.main.async {
                self.view.evaluateJavaScript("endStream()", completionHandler: nil)
            }

        case "stopRecording":
            guard isRecording else { return }
            isRecording = false
            recorder.onDone = { [weak self] url in
                guard let self = self, let url = url else {
                    DispatchQueue.main.async {
                        self?.view.evaluateJavaScript("onTranscription(null)", completionHandler: nil)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.view.evaluateJavaScript("onTranscribing()", completionHandler: nil)
                }
                transcribe(audioURL: url) { [weak self] text in
                    DispatchQueue.main.async {
                        if let t = text {
                            let escaped = t
                                .replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "'", with: "\\'")
                            self?.view.evaluateJavaScript("onTranscription('\(escaped)')",
                                completionHandler: nil)
                        } else {
                            self?.view.evaluateJavaScript("onTranscription(null)",
                                completionHandler: nil)
                        }
                    }
                }
            }
            recorder.stop()

        default: break
        }
    }

    func requestMicAndRecord() {
        // AVAudioApplication requiere macOS 14+, usar API compatible con macOS 13
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.startRecording() } }
                else {
                    DispatchQueue.main.async {
                        self?.view.evaluateJavaScript(
                            "onMicError('Permiso de micrófono denegado.')",
                            completionHandler: nil)
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.view.evaluateJavaScript(
                    "onMicError('Permiso denegado. Actívalo en Ajustes > Privacidad > Micrófono.')",
                    completionHandler: nil)
            }
        }
    }

    func startRecording() {
        isRecording = true
        recorder.start()
        view.evaluateJavaScript("onRecordingStarted()", completionHandler: nil)
    }

    func checkWhisperInstall() {
        let bins = [WHISPER_BIN, "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        let found = bins.contains { FileManager.default.fileExists(atPath: $0) }
        let hasModel = findWhisperModel() != nil
        view.evaluateJavaScript(
            "onWhisperStatus(\(found ? "true" : "false"), \(hasModel ? "true" : "false"))",
            completionHandler: nil)
    }

    func fetchModels() {
        guard let url = URL(string: "\(OLLAMA_BASE)/api/tags") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }
            let names = models.compactMap { $0["name"] as? String }
            let js = "receiveModels(\(jsonString(names)))"
            DispatchQueue.main.async { self.view.evaluateJavaScript(js, completionHandler: nil) }
        }.resume()
    }

    func streamResponse(prompt: String, model: String) {
        guard let url = URL(string: "\(OLLAMA_BASE)/api/generate") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "prompt": prompt, "stream": true
        ])
        currentStreamSession?.invalidateAndCancel()
        let session = URLSession(configuration: .default,
                                 delegate: StreamDelegate(webView: view),
                                 delegateQueue: nil)
        currentStreamSession = session
        session.dataTask(with: req).resume()
    }

    func loadHTML() {
        view.loadHTMLString(chatHTML(), baseURL: nil)
    }
}

// ── Stream delegate ───────────────────────────────────────────────────────────

class StreamDelegate: NSObject, URLSessionDataDelegate {
    let webView: WKWebView
    var buffer = Data()

    init(webView: WKWebView) { self.webView = webView }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        buffer.append(data)
        let str = String(data: buffer, encoding: .utf8) ?? ""
        let lines = str.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            guard !line.isEmpty, i < lines.count - 1 else { continue }
            if let d = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let token = json["response"] as? String {
                let escaped = token
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                DispatchQueue.main.async {
                    self.webView.evaluateJavaScript("appendToken(`\(escaped)`)",
                        completionHandler: nil)
                }
            }
        }
        buffer = lines.last.flatMap { $0.isEmpty ? nil : $0.data(using: .utf8) } ?? Data()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("endStream()", completionHandler: nil)
        }
    }
}

// ── HTML ──────────────────────────────────────────────────────────────────────

func jsonString(_ arr: [String]) -> String {
    (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
}

func chatHTML() -> String { return """
<!DOCTYPE html>
<html lang="es">
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
#model-wrap{position:relative;display:flex;align-items:center;gap:8px}
#model-btn{background:transparent;border:none;color:var(--muted);
  font-family:var(--font);font-size:11.5px;cursor:pointer;outline:none;
  -webkit-app-region:no-drag;padding:2px 6px;border-radius:3px;
  display:flex;align-items:center;gap:5px;transition:color .15s}
#model-btn:hover{color:var(--text)}
#model-name{color:var(--text)}
#model-dropdown{display:none;position:fixed;top:44px;left:14px;
  background:#1a1a1e;border:1px solid var(--border);border-radius:6px;
  min-width:200px;z-index:999;overflow-y:auto;max-height:calc(100vh - 60px);
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
#mic-btn.recording{border-color:var(--rec);color:var(--rec);
  animation:recpulse 1s ease-in-out infinite}
#mic-btn.transcribing{border-color:var(--muted);color:var(--muted);cursor:default}
@keyframes recpulse{0%,100%{box-shadow:0 0 0 0 rgba(248,113,113,.4)}
  50%{box-shadow:0 0 0 4px rgba(248,113,113,0)}}
#whisper-hint{font-size:10px;color:var(--muted);padding:4px 14px 0;
  display:none;letter-spacing:.03em}
#whisper-hint a{color:var(--accent);text-decoration:none}
#whisper-hint.visible{display:block}
</style>
</head>
<body>
<div id="app">
  <div id="header">
    <div id="model-wrap">
      <div id="dot"></div>
      <button id="model-btn">
        <span id="model-name">cargando…</span>
        <span style="color:var(--muted);font-size:9px">▾</span>
      </button>
      <div id="model-dropdown"></div>
    </div>
  </div>
  <div id="msgs"></div>
  <div id="whisper-hint"></div>
  <div id="bottom">
    <textarea id="inp" placeholder="Mensaje… (Enter)" rows="1"></textarea>
    <button id="mic-btn" class="action-btn" title="Clic para grabar">🎙</button>
    <button id="btn" class="action-btn">↵</button>
  </div>
</div>
<script>
let model = 'llama3.2', busy = false, currentBody = null;
let micState = 'idle'; // idle | recording | transcribing
let streaming = false;
let whisperOk = false;

window.webkit.messageHandlers.loadModels.postMessage({});
window.webkit.messageHandlers.checkWhisper.postMessage({});

// ── Modelo ────────────────────────────────────────────────────────────────────
const modelBtn      = document.getElementById('model-btn');
const modelName     = document.getElementById('model-name');
const modelDropdown = document.getElementById('model-dropdown');
modelBtn.addEventListener('click', e => { e.stopPropagation(); modelDropdown.classList.toggle('open'); });
document.addEventListener('click', () => modelDropdown.classList.remove('open'));

function receiveModels(models) {
  if (!models.length) return;
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
      modelDropdown.querySelectorAll('.model-opt').forEach(el =>
        el.classList.toggle('active', el.textContent === m));
      modelDropdown.classList.remove('open');
    });
    modelDropdown.appendChild(div);
  });
}

// ── Whisper status ────────────────────────────────────────────────────────────
function onWhisperStatus(hasBin, hasModel) {
  whisperOk = hasBin && hasModel;
  const hint = document.getElementById('whisper-hint');
  if (!hasBin) {
    hint.innerHTML = '⚠ whisper-cli no encontrado. Instala: <a href="#">brew install whisper-cpp</a>';
    hint.classList.add('visible');
  } else if (!hasModel) {
    hint.innerHTML = '⚠ Modelo no encontrado. Ejecuta: <code>whisper-download-model base</code>';
    hint.classList.add('visible');
  }
}

// ── Micrófono ─────────────────────────────────────────────────────────────────
const micBtn = document.getElementById('mic-btn');
const btn    = document.getElementById('btn');

micBtn.addEventListener('click', e => {
  e.preventDefault();
  if (micState === 'idle') {
    // Empezar grabación
    micState = 'recording';
    micBtn.classList.add('recording');
    micBtn.title = 'Clic para parar';
    window.webkit.messageHandlers.startRecording.postMessage({});
  } else if (micState === 'recording') {
    // Parar grabación
    micBtn.classList.remove('recording');
    micBtn.title = 'Clic para grabar';
    window.webkit.messageHandlers.stopRecording.postMessage({});
  }
  // Si está transcribiendo, ignorar clics
});

btn.addEventListener('click', e => {
  e.preventDefault();
  if (streaming) {
    // Stop Ollama
    window.webkit.messageHandlers.stopStream.postMessage({});
    streaming = false; busy = false;
    if (currentBody) currentBody.classList.remove('cursor');
    currentBody = null;
    btn.textContent = '↵';
    btn.classList.remove('stopping');
    return;
  }
  send();
});

function onRecordingStarted() {
  micState = 'recording';
}

function onTranscribing() {
  micState = 'transcribing';
  micBtn.classList.remove('recording');
  micBtn.classList.add('transcribing');
  micBtn.textContent = '⏳';
}

function onTranscription(text) {
  micState = 'idle';
  micBtn.classList.remove('recording', 'transcribing');
  micBtn.textContent = '🎙';
  if (text && text.trim()) {
    sendText(text.trim());
  }
}

function onMicError(msg) {
  micState = 'idle';
  micBtn.classList.remove('recording', 'transcribing');
  micBtn.textContent = '🎙';
  addMsg('err').textContent = msg;
}

// ── Chat ──────────────────────────────────────────────────────────────────────
function addMsg(role) {
  const c = document.getElementById('msgs'), d = document.createElement('div');
  d.className = 'msg ' + role;
  const L = {user:'tú', ai:model.split(':')[0], err:'error'};
  d.innerHTML = '<div class="lbl">' + (L[role]||role) + '</div><div class="body"></div>';
  c.appendChild(d); c.scrollTop = c.scrollHeight;
  return d.querySelector('.body');
}

function appendToken(t) {
  if (currentBody) {
    currentBody.textContent += t;
    document.getElementById('msgs').scrollTop = 999999;
  }
}

function endStream() {
  if (currentBody) currentBody.classList.remove('cursor');
  currentBody = null; busy = false; streaming = false;
  btn.textContent = '↵';
  btn.classList.remove('stopping');
}

function sendText(text) {
  if (busy || !text) return;
  modelDropdown.classList.remove('open');
  addMsg('user').textContent = text;
  currentBody = addMsg('ai');
  currentBody.classList.add('cursor');
  busy = true; streaming = true;
  btn.textContent = '⏹';
  btn.classList.add('stopping');
  window.webkit.messageHandlers.sendMessage.postMessage({prompt: text, model: model});
}

function send() {
  const inp = document.getElementById('inp');
  const text = inp.value.trim();
  if (!text) return;
  inp.value = ''; inp.style.height = 'auto';
  sendText(text);
}

// btn listener handled above
document.getElementById('inp').addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
  setTimeout(() => {
    e.target.style.height = 'auto';
    e.target.style.height = Math.min(e.target.scrollHeight, 72) + 'px';
  }, 0);
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