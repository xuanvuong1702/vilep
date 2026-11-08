// Capture the app at a desktop viewport (checks the responsive PageFrame).
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const outDir = process.argv[2] ?? 'shots';
const url = process.argv[3] ?? 'http://127.0.0.1:8080/#/discover';
mkdirSync(outDir, { recursive: true });

const target = await (await fetch('http://127.0.0.1:9222/json/new?about:blank', { method: 'PUT' })).json();
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.onopen = resolve;
  ws.onerror = reject;
});

let id = 1;
const pending = new Map();
ws.onmessage = (message) => {
  const data = JSON.parse(message.data);
  if (data.id && pending.has(data.id)) {
    const { resolve } = pending.get(data.id);
    pending.delete(data.id);
    resolve(data.result);
  }
};
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const msgId = id++;
    pending.set(msgId, { resolve });
    ws.send(JSON.stringify({ id: msgId, method, params }));
  });

await send('Page.enable');
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url });
await new Promise((resolve) => setTimeout(resolve, 6000));
const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
writeFileSync(join(outDir, 'desktop.png'), Buffer.from(shot.data, 'base64'));
console.log('captured desktop');
await fetch(`http://127.0.0.1:9222/json/close/${target.id}`);
ws.close();
