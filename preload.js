const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('api', {
  getEnv:        ()        => ipcRenderer.invoke('get-env'),
  probeStream:   (url)     => ipcRenderer.invoke('probe-stream', url),
  startScan:     (params)  => ipcRenderer.invoke('start-scan', params),
  stopScan:      ()        => ipcRenderer.invoke('stop-scan'),
  startSap:      (iface)   => ipcRenderer.invoke('start-sap', { iface }),
  stopSap:       ()        => ipcRenderer.invoke('stop-sap'),
  launchVlc:     (url)     => ipcRenderer.invoke('launch-vlc', url),
  saveM3u:       (c, n)    => ipcRenderer.invoke('save-m3u', { content: c, defaultName: n }),
  onScanResult:  cb => ipcRenderer.on('scan-result',  (_, d) => cb(d)),
  onScanDone:    cb => ipcRenderer.on('scan-done',    (_, d) => cb(d)),
  onSapAnnounce: cb => ipcRenderer.on('sap-announce', (_, d) => cb(d)),
  onSapReady:    cb => ipcRenderer.on('sap-ready',    (_, d) => cb(d)),
  onSapError:    cb => ipcRenderer.on('sap-error',    (_, d) => cb(d)),
  removeListeners: ch => ipcRenderer.removeAllListeners(ch),
});
