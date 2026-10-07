"""Minimal CDP helper for the Mixamo session on Chrome :9333 (token stays inside the page).
Usage: uv run --with websockets python tools/_mixamo_cdp.py nav <url>
       uv run --with websockets python tools/_mixamo_cdp.py eval '<js expression>'
"""
import asyncio, json, sys, urllib.request
import websockets


def page():
    tabs = json.load(urllib.request.urlopen('http://127.0.0.1:9333/json/list'))
    for t in tabs:
        if t['type'] == 'page' and 'mixamo' in t['url']:
            return t
    return next(t for t in tabs if t['type'] == 'page')


async def call(ws, i, method, params=None):
    await ws.send(json.dumps({'id': i, 'method': method, 'params': params or {}}))
    while True:
        m = json.loads(await ws.recv())
        if m.get('id') == i:
            return m


async def main():
    t = page()
    async with websockets.connect(t['webSocketDebuggerUrl'], max_size=2**26) as ws:
        if sys.argv[1] == 'nav':
            print(await call(ws, 1, 'Page.navigate', {'url': sys.argv[2]}))
        else:
            r = await call(ws, 1, 'Runtime.evaluate', {'expression': sys.argv[2], 'awaitPromise': True, 'returnByValue': True, 'timeout': 60000})
            print(json.dumps(r.get('result', {}).get('result', {}).get('value', r), ensure_ascii=False)[:20000])


asyncio.run(main())
