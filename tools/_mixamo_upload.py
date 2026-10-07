"""Upload one NPC FBX to Mixamo through the logged-in tab (UPLOAD CHARACTER → file input → NEXT…), then print
the new character uuid / name / status. Usage: uv run --with websockets python tools/_mixamo_upload.py <fbx>
"""
import asyncio, json, sys, time, urllib.request
import websockets

FBX = sys.argv[1]


async def main():
    tabs = json.load(urllib.request.urlopen('http://127.0.0.1:9333/json/list'))
    t = next(t for t in tabs if t['type'] == 'page' and 'mixamo' in t['url'])
    async with websockets.connect(t['webSocketDebuggerUrl'], max_size=2**26) as ws:
        n = [0]

        async def call(method, params=None):
            n[0] += 1
            await ws.send(json.dumps({'id': n[0], 'method': method, 'params': params or {}}))
            while True:
                m = json.loads(await ws.recv())
                if m.get('id') == n[0]:
                    return m

        async def ev(expr):
            r = await call('Runtime.evaluate', {'expression': expr, 'awaitPromise': True, 'returnByValue': True})
            return r.get('result', {}).get('result', {}).get('value')

        H = "{'X-Api-Key':'mixamo2','Authorization':'Bearer '+localStorage.access_token}"
        before = await ev(f"(async()=>(await (await fetch('/api/v1/characters/primary',{{headers:{H}}})).json()))()")
        print('primary before', before)
        print('click upload', await ev("(()=>{const b=[...document.querySelectorAll('button')].find(b=>b.innerText.trim()=='UPLOAD CHARACTER'); if(!b) return false; b.click(); return true})()"))
        await asyncio.sleep(2)
        doc = await call('DOM.getDocument', {'depth': -1})
        q = await call('DOM.querySelector', {'nodeId': doc['result']['root']['nodeId'], 'selector': 'input[type=file]'})
        nid = q['result']['nodeId']
        print('file input node', nid)
        print('set files', await call('DOM.setFileInputFiles', {'nodeId': nid, 'files': [FBX]}))
        t0 = time.time()
        last = ''
        while time.time() - t0 < 400:
            await asyncio.sleep(4)
            txt = await ev("(()=>{const m=document.querySelector('.modal, .modal-dialog, [role=dialog]'); return m? m.innerText.slice(0,300):''})()")
            if txt != last:
                print('modal:', (txt or '').replace('\n', ' | ')); last = txt
            clicked = await ev("(()=>{const b=[...document.querySelectorAll('.modal button, [role=dialog] button')].find(b=>/^(NEXT|FINISH)$/i.test(b.innerText.trim()) && !b.disabled); if(b){b.click(); return b.innerText.trim()} return ''})()")
            if clicked:
                print('clicked', clicked)
            prim = await ev(f"(async()=>(await (await fetch('/api/v1/characters/primary',{{headers:{H}}})).json()))()")
            if prim and before and prim.get('primary_character_id') != before.get('primary_character_id') and not txt:
                cid = prim['primary_character_id']
                mon = await ev(f"(async()=>(await (await fetch('/api/v1/characters/{cid}/monitor',{{headers:{H}}})).json()))()")
                print('NEW', json.dumps(prim, ensure_ascii=False), 'monitor', json.dumps(mon)[:200])
                return
        print('TIMEOUT')


asyncio.run(main())
