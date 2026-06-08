const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const { spawn } = require('child_process');
const path  = require('path');
const fs    = require('fs');
const os    = require('os');
const dgram = require('dgram');

function findFfprobe() {
  if (process.platform === 'win32') {
    const c = ['C:\\ffmpeg\\bin\\ffprobe.exe','C:\\Program Files\\ffmpeg\\bin\\ffprobe.exe','C:\\ProgramData\\chocolatey\\bin\\ffprobe.exe','C:\\tools\\ffmpeg\\bin\\ffprobe.exe'];
    for (const p of c) if (fs.existsSync(p)) return p;
    return 'ffprobe.exe';
  }
  if (process.platform === 'darwin') {
    for (const p of ['/opt/homebrew/bin/ffprobe','/usr/local/bin/ffprobe','/usr/bin/ffprobe']) if (fs.existsSync(p)) return p;
  }
  return 'ffprobe';
}

function findVlc() {
  if (process.platform === 'win32') {
    for (const p of ['C:\\Program Files\\VideoLAN\\VLC\\vlc.exe','C:\\Program Files (x86)\\VideoLAN\\VLC\\vlc.exe']) if (fs.existsSync(p)) return p;
    return 'vlc.exe';
  }
  if (process.platform === 'darwin') return '/Applications/VLC.app/Contents/MacOS/VLC';
  return 'vlc';
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1400, height: 920, minWidth: 1000, minHeight: 680,
    backgroundColor: '#0d0f0e',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false },
    title: 'Multicast Ring Tester', show: false,
  });
  win.loadFile('index.html');
  win.once('ready-to-show', () => win.show());
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });

function probeUrl(url, timeoutMs) {
  return new Promise(resolve => {
    const ffprobe = findFfprobe();
    const µs = Math.max(1000000, (timeoutMs - 1500) * 1000);
    const args = ['-v','quiet','-print_format','json','-show_streams','-show_format','-timeout',String(µs),'-fflags','nobuffer',url];
    let stdout = '';
    let proc;
    const kill = setTimeout(() => { try { proc.kill('SIGKILL'); } catch {} resolve({ error: 'timeout' }); }, timeoutMs);
    try { proc = spawn(ffprobe, args); }
    catch (e) { clearTimeout(kill); resolve({ error: 'not_found', message: e.message }); return; }
    proc.stdout.on('data', d => { stdout += d.toString(); });
    proc.on('close', () => {
      clearTimeout(kill);
      if (!stdout) { resolve({ error: 'no_signal' }); return; }
      try { resolve({ ok: true, raw: JSON.parse(stdout) }); }
      catch { resolve({ error: 'parse_error' }); }
    });
    proc.on('error', err => { clearTimeout(kill); resolve({ error: 'not_found', message: err.message }); });
  });
}

ipcMain.handle('probe-stream', (_e, url) => probeUrl(url, 9000));

let scanCtx = { running: false, cancel: false };

async function runScan(event, { prefix, start, end, port, iface, concurrency, probeSecs }) {
  const total = end - start + 1;
  const timeoutMs = Math.max(3000, ((parseInt(probeSecs)||5) * 1000) + 1000);
  const concurrent = Math.min(Math.max(1, parseInt(concurrency)||10), 24);
  const addrs = [];
  for (let i = start; i <= end; i++) addrs.push(prefix + '.' + i);
  let idx = 0, completed = 0, found = 0;
  const send = (ch, data) => { if (!event.sender.isDestroyed()) event.sender.send(ch, data); };
  async function worker() {
    while (idx < addrs.length && !scanCtx.cancel) {
      const ip = addrs[idx++];
      const base = 'udp://@' + ip + ':' + port;
      const url = iface ? base + '?localaddr=' + iface : base;
      const res = await probeUrl(url, timeoutMs);
      completed++;
      if (res.ok) found++;
      send('scan-result', { ip, port, url, result: res, progress: { completed, total, found } });
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrent, addrs.length) }, worker));
  scanCtx.running = false;
  send('scan-done', { total, completed, found, cancelled: scanCtx.cancel });
}

ipcMain.handle('start-scan', (event, params) => {
  if (scanCtx.running) return { error: 'already_running' };
  scanCtx = { running: true, cancel: false };
  runScan(event, params);
  return { ok: true };
});
ipcMain.handle('stop-scan', () => { scanCtx.cancel = true; return { ok: true }; });

let sapSock = null;
ipcMain.handle('start-sap', (event, { iface }) => {
  if (sapSock) return { error: 'already_running' };
  const sock = dgram.createSocket({ type: 'udp4', reuseAddr: true });
  const send = (ch, d) => { if (!event.sender.isDestroyed()) event.sender.send(ch, d); };
  sock.on('error', err => { send('sap-error', { message: err.message }); sock.close(); sapSock = null; });
  sock.on('message', (msg, rinfo) => { const p = parseSap(msg); if (p) send('sap-announce', { ...p, from: rinfo.address }); });
  sock.bind(9875, () => {
    try { sock.addMembership('224.2.127.254', iface || undefined); sock.setMulticastLoopback(false); send('sap-ready', {}); }
    catch (e) { send('sap-error', { message: 'Could not join SAP group: ' + e.message }); }
  });
  sapSock = sock;
  return { ok: true };
});
ipcMain.handle('stop-sap', () => { if (sapSock) { try { sapSock.close(); } catch {} sapSock = null; } return { ok: true }; });

function parseSap(buf) {
  if (buf.length < 8) return null;
  const flags = buf[0];
  if (((flags >> 5) & 0x07) !== 1) return null;
  if (flags & 0x04) return null;
  const authLen = buf[1];
  let offset = 8 + authLen * 4;
  if (offset >= buf.length) return null;
  let text = buf.slice(offset).toString('utf8');
  const nul = text.indexOf('\0');
  if (nul >= 0 && nul < 40) text = text.slice(nul + 1);
  return parseSdp(text);
}

function parseSdp(sdp) {
  const r = { name: null, address: null, port: null, mediaType: null };
  for (const raw of sdp.split(/\r?\n/)) {
    if (raw.length < 2 || raw[1] !== '=') continue;
    const k = raw[0], v = raw.slice(2).trim();
    if (k === 's') r.name = v || null;
    if (k === 'c') { const p = v.split(' '); if (p[2]) r.address = p[2].split('/')[0]; }
    if (k === 'm') { const p = v.split(' '); r.mediaType = p[0]; r.port = parseInt(p[1]) || null; }
  }
  return (r.address && r.port) ? r : null;
}

ipcMain.handle('launch-vlc', (_e, url) => {
  try { const p = spawn(findVlc(), [url], { detached: true, stdio: 'ignore' }); p.unref(); return { ok: true }; }
  catch (e) { return { error: e.message }; }
});

ipcMain.handle('save-m3u', async (_e, { content, defaultName }) => {
  const { filePath, canceled } = await dialog.showSaveDialog({
    defaultPath: defaultName,
    filters: [{ name: 'M3U Playlist', extensions: ['m3u'] }],
  });
  if (canceled || !filePath) return { cancelled: true };
  fs.writeFileSync(filePath, content, 'utf8');
  return { ok: true, filePath };
});

ipcMain.handle('get-env', () => {
  const fp = findFfprobe(), vl = findVlc();
  const nics = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs) {
      if ((a.family === 'IPv4' || a.family === 4) && !a.internal)
        nics.push({ name, address: a.address, netmask: a.netmask });
    }
  }
  return {
    platform: process.platform, ffprobe: fp,
    ffprobeFound: path.isAbsolute(fp) ? fs.existsSync(fp) : null,
    vlc: vl, vlcFound: path.isAbsolute(vl) ? fs.existsSync(vl) : null,
    nics, version: app.getVersion(),
  };
});
