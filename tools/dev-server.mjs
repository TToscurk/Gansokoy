/**
 * Static dev server for the shrine.
 *
 * Exists instead of `python -m http.server` for one reason: ES module caching.
 * The browser keeps its own module registry, and a plain reload will happily
 * re-run main.js against STALE copies of ./src/*.js — you edit a file, reload,
 * and silently get the old behaviour. Every response here is `no-store`, so a
 * reload always re-fetches every module.
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(process.argv[2] ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '..'));
const PORT = Number(process.argv[3] ?? 5603);

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  let file = path.join(ROOT, url === '/' ? 'index.html' : url);

  // keep requests inside ROOT
  if (!file.startsWith(ROOT)) {
    res.writeHead(403).end('forbidden');
    return;
  }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) {
    res.writeHead(404, { 'Content-Type': 'text/plain' }).end('not found: ' + url);
    console.log('404', url);
    return;
  }

  res.writeHead(200, {
    'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream',
    'Cache-Control': 'no-store, no-cache, must-revalidate',
    'Pragma': 'no-cache',
  });
  fs.createReadStream(file).pipe(res);
}).listen(PORT, () => console.log(`shrine dev server → http://localhost:${PORT}  (root: ${ROOT}, no-store)`));
