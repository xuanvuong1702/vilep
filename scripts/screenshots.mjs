// Capture screenshots of the Flutter web build through the Chrome DevTools Protocol.
// Usage: node scripts/screenshots.mjs <outDir> [baseUrl]
// Requires Edge/Chrome listening on 127.0.0.1:9222 (see scripts/serve-web.ps1).
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const outDir = process.argv[2] ?? 'shots';
const base = process.argv[3] ?? 'http://127.0.0.1:8080';
const api = process.argv[4] ?? 'http://127.0.0.1:5080';
mkdirSync(outDir, { recursive: true });

async function json(url) {
  const response = await fetch(url);
  return response.json();
}

const feed = await json(`${api}/api/v1/cases?tab=need&limit=6`);
const items = feed?.data?.items ?? [];
const firstCase = items.find((item) => item.percent > 40) ?? items[0];
const closedShare = await json(`${api}/api/v1/share/tet01`);
const closedCaseId = closedShare?.data?.caseId;

const pages = [
  ['01-feed', '/#/discover'],
  ['02-case-detail', firstCase ? `/#/case/${firstCase.id}` : null],
  ['03-contribute-sheet', firstCase ? `/#/case/${firstCase.id}` : null, { click: [290, 887], waitAfter: 2200 }],
  ['04-my-cases', '/#/my'],
  ['05-profile', '/#/me'],
  ['06-notifications', '/#/notifications'],
  ['07-create', '/#/create'],
  ['08-creditor-invite', '/#/creditor/demo-caphe'],
  ['09-certificate', closedCaseId ? `/#/certificate/${closedCaseId}` : null],
].filter(([, path]) => Boolean(path));

const target = await (await fetch('http://127.0.0.1:9222/json/new?about:blank', { method: 'PUT' })).json();
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  ws.onopen = resolve;
  ws.onerror = reject;
});

let nextId = 1;
const pending = new Map();
const events = new Map();

ws.onmessage = (message) => {
  const data = JSON.parse(message.data);
  if (data.id && pending.has(data.id)) {
    const { resolve, reject } = pending.get(data.id);
    pending.delete(data.id);
    data.error ? reject(new Error(JSON.stringify(data.error))) : resolve(data.result);
    return;
  }
  if (data.method && events.has(data.method)) {
    const handlers = events.get(data.method);
    events.delete(data.method);
    handlers.forEach((handler) => handler(data.params));
  }
};

const send = (method, params = {}) =>
  new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });

const once = (method, timeoutMs = 20000) =>
  new Promise((resolve) => {
    events.set(method, [...(events.get(method) ?? []), resolve]);
    setTimeout(() => resolve(null), timeoutMs);
  });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const click = async ([x, y]) => {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(60);
  }
};

await send('Page.enable');
await send('Runtime.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 430, height: 932, deviceScaleFactor: 2, mobile: true });

for (const [name, path, action] of pages) {
  const loaded = once('Page.loadEventFired');
  await send('Page.navigate', { url: base + path });
  await loaded;
  await sleep(4200);
  if (action?.click) {
    await click(action.click);
    await sleep(action.waitAfter ?? 1800);
  }
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  writeFileSync(join(outDir, `${name}.png`), Buffer.from(shot.data, 'base64'));
  console.log(`captured ${name}`);
}

await fetch(`http://127.0.0.1:9222/json/close/${target.id}`);
ws.close();
