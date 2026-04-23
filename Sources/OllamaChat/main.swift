import AppKit
import Foundation

// ── Constantes ────────────────────────────────────────────────────────────────

let OLLAMA_BASE = "http://localhost:11434"
var currentModel = "llama3.2"

// ── AppDelegate ───────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var chatWindow: ChatWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sin icono en el Dock
        NSApp.setActivationPolicy(.accessory)

        // Menubar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "⬡"
            button.action = #selector(toggleChat)
            button.target = self
        }

        // Menú
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Abrir chat", action: #selector(toggleChat), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func toggleChat() {
        if chatWindow == nil {
            chatWindow = ChatWindow()
        }
        chatWindow?.showAndFocus()
    }

    @objc func quit() {
        NSApp.terminate(nil)
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

        // ★ CLAVE: excluir de screen sharing — API pública AppKit
        window.sharingType = .none

        webView = WKWebViewWrapper(frame: frame)
        window.contentView = webView.view

        super.init()
        window.delegate = self
    }

    func showAndFocus() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Reaplicar tras mostrar por si acaso
        window.sharingType = .none
    }

    func windowWillClose(_ notification: Notification) {
        // No destruir, solo ocultar
    }
}

// ── WKWebView wrapper ─────────────────────────────────────────────────────────

import WebKit

class WKWebViewWrapper: NSObject, WKScriptMessageHandler {
    let view: WKWebView
    var streamTask: URLSessionDataTask?

    init(frame: NSRect = .zero) {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController

        view = WKWebView(frame: frame, configuration: config)
        view.setValue(false, forKey: "drawsBackground")

        super.init()

        contentController.add(self, name: "sendMessage")
        contentController.add(self, name: "loadModels")

        loadHTML()
    }

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String] else { return }

        if message.name == "sendMessage",
           let prompt = body["prompt"],
           let model = body["model"] {
            streamResponse(prompt: prompt, model: model)
        } else if message.name == "loadModels" {
            fetchModels()
        }
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

        let session = URLSession(configuration: .default,
                                 delegate: StreamDelegate(webView: view),
                                 delegateQueue: nil)
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

    init(webView: WKWebView) {
        self.webView = webView
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        buffer.append(data)
        let str = String(data: buffer, encoding: .utf8) ?? ""
        let lines = str.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            guard i < lines.count - 1 else { break } // última línea puede estar incompleta
            if let d = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let token = json["response"] as? String {
                let escaped = token
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                let js = "appendToken(`\(escaped)`)"
                DispatchQueue.main.async {
                    self.webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
        // Guardar solo la última línea incompleta en buffer
        if let last = lines.last, !last.isEmpty {
            buffer = last.data(using: .utf8) ?? Data()
        } else {
            buffer = Data()
        }
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

func chatHTML() -> String {
    return """
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
  --user:#7dd3fc;--error:#f87171;
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
  padding:9px 14px;display:flex;align-items:flex-end;gap:8px;flex-shrink:0}
#inp{flex:1;background:transparent;border:none;color:var(--text);
  font-family:var(--font);font-size:12.5px;outline:none;resize:none;
  line-height:1.5;max-height:72px;overflow-y:auto;caret-color:var(--accent)}
#inp::placeholder{color:var(--muted)}
#btn{background:none;border:1px solid var(--border);color:var(--muted);
  font-family:var(--font);font-size:13px;padding:3px 8px;border-radius:4px;
  cursor:pointer;transition:all .15s;flex-shrink:0;margin-bottom:1px}
#btn:hover{border-color:var(--accent);color:var(--accent)}
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
  <div id="bottom">
    <textarea id="inp" placeholder="Mensaje… (Enter)" rows="1"></textarea>
    <button id="btn">↵</button>
  </div>
</div>
<script>
let model = 'llama3.2', busy = false, currentBody = null;

window.webkit.messageHandlers.loadModels.postMessage({});

const modelBtn      = document.getElementById('model-btn');
const modelName     = document.getElementById('model-name');
const modelDropdown = document.getElementById('model-dropdown');

modelBtn.addEventListener('click', e => {
  e.stopPropagation();
  modelDropdown.classList.toggle('open');
});
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
      e.stopPropagation();
      model = m;
      modelName.textContent = m.split(':')[0];
      modelDropdown.querySelectorAll('.model-opt').forEach(el =>
        el.classList.toggle('active', el.textContent === m));
      modelDropdown.classList.remove('open');
    });
    modelDropdown.appendChild(div);
  });
}

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
  currentBody = null; busy = false;
}

function send() {
  if (busy) return;
  const inp = document.getElementById('inp'), text = inp.value.trim();
  if (!text) return;
  inp.value = ''; inp.style.height = 'auto';
  modelDropdown.classList.remove('open');
  addMsg('user').textContent = text;
  currentBody = addMsg('ai');
  currentBody.classList.add('cursor');
  busy = true;
  window.webkit.messageHandlers.sendMessage.postMessage({prompt: text, model: model});
}

document.getElementById('btn').addEventListener('click', send);
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
"""
}


// ── Entry point ───────────────────────────────────────────────────────────────

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()