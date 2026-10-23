"""慧音專屬待機候選 — Mixamo 下載（skin false、30 fps、不減 key、arm-space 0.30＝同 NPC 管線）。
沿用 tools/mixamo_fetch_r3c1.py 的流程：Chrome :9333 已登入的 Mixamo 分頁內 export → monitor → S3 取檔；
token 與簽名網址只留在本行程（不印、不寫）。角色＝使用者上傳的 Keine_Mixamo（primary）。
輸出 godot/characters/keine/anim/src/<clip>_a030.fbx ＋ provenance <clip>_a030_download.json
Usage: uv run --with websockets python tools/mixamo_fetch_keine.py
"""
import asyncio, hashlib, json, urllib.request
from pathlib import Path
import websockets

R = Path(__file__).resolve().parents[1]
OUT = R / 'godot/characters/keine/anim/src'
CHAR = '33fd271c-74b9-48c9-95d7-00e1cc1478a1'   # Keine_Mixamo（Mixamo primary character）
ARM = 0.30
JOBS = [
    ('idle_thinking', 'c9c990e8-b96c-11e4-a802-0aaa78deedf9', 'JEV shortlist r2: Thinking While Standing (118030901)'),
    ('idle_lookaround02', 'edc148eb-b0a1-4a9f-80a1-20a72b60456b', 'JEV shortlist r2: Standing Idle 02 Looking Around (128670924)'),
    ('idle_weightshift', 'c9c79c65-b96c-11e4-a802-0aaa78deedf9', 'JEV shortlist r2: Weight Shift Idle (113410901)'),
    ('walk_careful', 'c9c7fda5-b96c-11e4-a802-0aaa78deedf9', 'JEV shortlist r2: Careful Walk (113970901)'),
    ('walk_feminine_fwd', 'c9c987f5-b96c-11e4-a802-0aaa78deedf9', 'JEV shortlist r2: Feminine Walk Forward (117660901)'),
    ('walk_female124', 'c9ccf814-b96c-11e4-a802-0aaa78deedf9', 'JEV shortlist r2: Female Walk 124540901 (124540901)'),
]
JS = r'''
(async (pid, cid, arm, wantInplace) => {
  const h = {'X-Api-Key': 'mixamo2', 'Authorization': 'Bearer ' + localStorage.access_token, 'Content-Type': 'application/json'};
  const d = await (await fetch(`/api/v1/products/${pid}?similar=0&character_id=${cid}`, {headers: h})).json();
  const g = d.details.gms_hash;
  const params = g.params.map(p => p[1]).join(',');
  const hash = {'model-id': g['model-id'], mirror: false, trim: g.trim, overdrive: 0, params: params, 'arm-space': arm, inplace: (wantInplace && d.details.supports_inplace) ? true : g.inplace};
  const body = {gms_hash: [hash], preferences: {format: 'fbx7_2019', skin: 'false', fps: '30', reducekf: '0'},
                character_id: cid, type: 'Motion', product_name: d.name};
  const e = await fetch('/api/v1/animations/export', {method: 'POST', headers: h, body: JSON.stringify(body)});
  const ej = await e.json();
  if (!ej.uuid && !ej.job_uuid) return {ok: false, err: JSON.stringify(ej).slice(0, 300)};
  const job = ej.job_uuid || ej.uuid;
  for (let i = 0; i < 60; i++) {
    await new Promise(r => setTimeout(r, 3000));
    const m = await (await fetch(`/api/v1/characters/${cid}/monitor`, {headers: h})).json();
    if (m.job_uuid !== job) continue;
    if (m.status === 'completed') return {ok: true, job, url: m.job_result, name: d.name, motion: hash, raw_params: g.params,
                                           frames: d.details.default_frame_length, duration: d.details.duration, supports_inplace: d.details.supports_inplace};
    if (m.status === 'failed') return {ok: false, job, err: String(m.job_result).slice(0, 300)};
  }
  return {ok: false, job, err: 'timeout'};
})'''


async def main():
    tabs = json.load(urllib.request.urlopen('http://127.0.0.1:9333/json/list'))
    t = next(t for t in tabs if t['type'] == 'page' and 'mixamo' in t['url'])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / '.gdignore').touch()
    async with websockets.connect(t['webSocketDebuggerUrl'], max_size=2**26) as ws:
        for i, (clip, pid, purpose) in enumerate(JOBS):
            tag = f'{clip}_a{int(round(ARM * 100)):03d}'
            out = OUT / f'{tag}.fbx'
            if out.exists():
                print('skip (exists)', out.name); continue
            expr = f'{JS}({json.dumps(pid)},{json.dumps(CHAR)},{ARM},{json.dumps(clip.startswith("walk"))})'
            await ws.send(json.dumps({'id': i + 1, 'method': 'Runtime.evaluate',
                                      'params': {'expression': expr, 'awaitPromise': True, 'returnByValue': True, 'timeout': 240000}}))
            while True:
                m = json.loads(await ws.recv())
                if m.get('id') == i + 1:
                    break
            res = m.get('result', {}).get('result', {}).get('value') or {'ok': False, 'err': str(m)[:300]}
            if not res.get('ok'):
                print('FAIL', tag, res.get('err')); continue
            urllib.request.urlretrieve(res.pop('url'), out)
            data = out.read_bytes()
            prov = {'character': 'keine', 'clip': tag, 'product': pid, 'arm_space': ARM, 'job_uuid': res['job'],
                    'character_uuid': CHAR, 'motion': res['motion'], 'raw_params': res['raw_params'], 'name': res['name'],
                    'mixamo_frames': res['frames'], 'mixamo_duration': res['duration'],
                    'preferences': {'format': 'fbx7_2019', 'skin': 'false', 'fps': '30', 'reducekf': '0'}, 'purpose': purpose,
                    'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            (OUT / f'{tag}_download.json').write_text(json.dumps(prov, ensure_ascii=False, indent=2), encoding='utf-8')
            print('OK', tag, res['name'], len(data), 'bytes', 'frames', res['frames'], 'inplace', res['motion']['inplace'], 'supports', res.get('supports_inplace'))


asyncio.run(main())
