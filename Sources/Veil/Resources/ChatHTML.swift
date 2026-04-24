import Foundation

func jsonString(_ arr: [String]) -> String {
    (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
}

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
    <button id="mic-btn" class="action-btn" title="Record">🎙</button>
    <button id="btn" class="action-btn">↵</button>
  </div>
</div>
<script>
let model = '', busy = false, currentBody = null;
let micState = 'idle', streaming = false;
let autoScroll = true;
let hasScreenshot = false;
let messages = [];
const CTX_WINDOW = 20; // max messages sent to API (keeps last N)

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

function shortcutLabel() {
  let s = '';
  if (shortcut.ctrl)  s += '⌃';
  if (shortcut.opt)   s += '⌥';
  if (shortcut.shift) s += '⇧';
  if (shortcut.cmd)   s += '⌘';
  s += shortcut.key.toUpperCase();
  return s || '—';
}

function toggleMic() {
  if (micState === 'idle') {
    micState = 'recording';
    micBtn.classList.add('recording');
    micBtn.title = 'Stop (' + shortcutLabel() + ')';
    window.webkit.messageHandlers.startRecording.postMessage({});
  } else if (micState === 'recording') {
    micBtn.classList.remove('recording');
    micBtn.title = 'Record (' + shortcutLabel() + ')';
    window.webkit.messageHandlers.stopRecording.postMessage({});
  }
}

micBtn.addEventListener('click', e => { e.preventDefault(); toggleMic(); });

let shortcut = {cmd:true, opt:true, ctrl:false, shift:false, key:''};
function setShortcut(s) { shortcut = s; }

const MOD_KEYS = new Set(['Meta','Alt','Control','Shift']);
let _scArmed = false;

document.addEventListener('keydown', e => {
  if (shortcut.key) {
    if (e.metaKey===shortcut.cmd && e.altKey===shortcut.opt &&
        e.ctrlKey===shortcut.ctrl && e.shiftKey===shortcut.shift &&
        e.key.toLowerCase()===shortcut.key) {
      e.preventDefault(); toggleMic();
    }
    return;
  }
  const modsMatch = e.metaKey===shortcut.cmd && e.altKey===shortcut.opt &&
                    e.ctrlKey===shortcut.ctrl && e.shiftKey===shortcut.shift;
  if (modsMatch && MOD_KEYS.has(e.key)) { _scArmed = true; }
  else { _scArmed = false; }
});

document.addEventListener('keyup', e => {
  if (_scArmed && MOD_KEYS.has(e.key)) { _scArmed = false; toggleMic(); }
});

btn.addEventListener('click', e => {
  e.preventDefault();
  if (streaming) {
    window.webkit.messageHandlers.stopStream.postMessage({});
    streaming = false; busy = false;
    if (currentBody) {
      if (!currentBody.textContent) messages.pop(); // remove user msg if no response yet
      currentBody.classList.remove('cursor');
    }
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
  micBtn.title = 'Record (' + shortcutLabel() + ')';
  if (text && text.trim()) sendText(text.trim());
}

function onMicError(msg) {
  micState = 'idle';
  micBtn.classList.remove('recording','transcribing');
  micBtn.textContent = '🎙';
  micBtn.title = 'Record (' + shortcutLabel() + ')';
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
  if (currentBody) {
    messages.push({role: 'assistant', content: currentBody.textContent});
    currentBody.classList.remove('cursor');
  }
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
  messages.push({role: 'user', content: text});
  if (hasScreenshot) clearScreenshotUI();
  const ctx = messages.length > CTX_WINDOW ? messages.slice(-CTX_WINDOW) : messages;
  window.webkit.messageHandlers.sendMessage.postMessage({messages: ctx, model: model});
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
