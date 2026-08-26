/* Tiny dev helper: receives a data-URL screenshot from the page and writes it to disk. */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const OUT = path.resolve(process.argv[2] ?? 'shots');
fs.mkdirSync(OUT, { recursive: true });

http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', '*');
  if (req.method === 'OPTIONS') return res.end();
  if (req.method !== 'POST') return res.end('ok');

  const name = (new URL(req.url, 'http://x').searchParams.get('name') || 'shot') + '.png';
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const b64 = body.split(',')[1] ?? '';
    const file = path.join(OUT, name);
    fs.writeFileSync(file, Buffer.from(b64, 'base64'));
    console.log('wrote', file, Math.round(b64.length / 1024) + 'KB');
    res.end(file);
  });
}).listen(5600, () => console.log('capture server on :5600 ->', OUT));
