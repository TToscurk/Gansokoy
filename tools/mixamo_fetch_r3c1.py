"""R3c.1 Readability Pass — Mixamo candidate downloads (skin false, 30 fps, no keyframe reduction).
Runs export → monitor → S3 fetch sequentially through the logged-in Mixamo tab on Chrome :9333.
The access token and the signed S3 URL stay inside this process (never printed / written).
Provenance per clip → docs/art_review/village_v2_p10_population/activity_r1c1/candidates/<cid>_<clip>_download.json
Usage: uv run --with websockets python tools/mixamo_fetch_r3c1.py
"""
import asyncio, hashlib, json, urllib.request
from pathlib import Path
import websockets

R = Path(__file__).resolve().parents[1]
PROV = R / 'docs/art_review/village_v2_p10_population/activity_r1c1/candidates'
CHAR = {'yakusou_f01': 'eada89a7-1521-4409-a5cd-bde5a36c0239', 'sakanaya_m01': 'e63ec18d-d4fe-43a2-a580-886f25781b38',
        'shufu_f01': '122e40ca-882a-4fb6-8977-657a5a7873ec',
        # uploaded 2026-10-07 for R3c.1 (tools/_mixamo_upload.py, NPCLIB export_npc_mixamo_upload.py, albedo 1024)
        'yaoya_m01': 'ad732041-6237-4e5e-9ea7-a1a2c18b4c37', 'chonin_m01': 'd7251734-978a-4cfa-b9d5-6ccea482214d'}
ARM = {'yakusou_f01': 0.30, 'sakanaya_m01': 0.38, 'shufu_f01': 0.30, 'yaoya_m01': 0.30, 'chonin_m01': 0.30}   # same arm-space as the R3c / NPCLIB clips of each NPC
JOBS = [
    ('yakusou_f01', 'sit_talk_a', 'c9cd7793-b96c-11e4-a802-0aaa78deedf9', None, 'Sit readability: seated vendor talking'),
    ('yakusou_f01', 'sit_talk_b', 'c9cd76b1-b96c-11e4-a802-0aaa78deedf9', None, 'Sit readability: seated vendor talking (variant)'),
    ('yakusou_f01', 'talk_twohands', 'c9c6fd7b-b96c-11e4-a802-0aaa78deedf9', None, 'Talk readability: asking with two hands'),
    ('yakusou_f01', 'argue', 'c9cd7855-b96c-11e4-a802-0aaa78deedf9', None, 'Talk readability: standing arguing (large gestures)'),
    ('yakusou_f01', 'talk_funny', 'c9c6ddb2-b96c-11e4-a802-0aaa78deedf9', None, 'Talk readability: talking, finding something funny'),
    ('shufu_f01', 'talk_twohands', 'c9c6fd7b-b96c-11e4-a802-0aaa78deedf9', None, 'Talk readability: asking with two hands'),
    ('sakanaya_m01', 'holding_walk', 'c9cda1e7-b96c-11e4-a802-0aaa78deedf9', True, 'Carry readability: walking while holding goods (in place)'),
    ('sakanaya_m01', 'bag_walk', 'c9c64027-b96c-11e4-a802-0aaa78deedf9', True, 'Carry readability: walking with a bag/bucket in one hand (in place)'),
    ('sakanaya_m01', 'bag_walk_rm', 'c9c64027-b96c-11e4-a802-0aaa78deedf9', False, 'Carry: same clip with root motion, stride measurement only'),
    ('yaoya_m01', 'box_idle', 'c9cd8d90-b96c-11e4-a802-0aaa78deedf9', None, 'Carry readability: vendor holding a crate of goods toward the customer'),
    ('sakanaya_m01', 'holding_walk_rm', 'c9cda1e7-b96c-11e4-a802-0aaa78deedf9', False, 'Carry: same clip with root motion, stride measurement only'),
]
JS = r'''
(async (pid, cid, inplace, arm, name) => {
  const h = {'X-Api-Key': 'mixamo2', 'Authorization': 'Bearer ' + localStorage.access_token, 'Content-Type': 'application/json'};
  const d = await (await fetch(`/api/v1/products/${pid}?similar=0&character_id=${cid}`, {headers: h})).json();
  const g = d.details.gms_hash;
  const params = g.params.map(p => p[1]).join(',');
  const ip = (inplace === null) ? g.inplace : (d.details.supports_inplace ? inplace : false);
  const hash = {'model-id': g['model-id'], mirror: false, trim: g.trim, overdrive: 0, params: params, 'arm-space': arm, inplace: ip};
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
                                           supports_inplace: d.details.supports_inplace, frames: d.details.default_frame_length, duration: d.details.duration};
    if (m.status === 'failed') return {ok: false, job, err: String(m.job_result).slice(0, 300)};
  }
  return {ok: false, job, err: 'timeout'};
})'''


async def main():
    tabs = json.load(urllib.request.urlopen('http://127.0.0.1:9333/json/list'))
    t = next(t for t in tabs if t['type'] == 'page' and 'mixamo' in t['url'])
    PROV.mkdir(parents=True, exist_ok=True)
    async with websockets.connect(t['webSocketDebuggerUrl'], max_size=2**26) as ws:
        for i, (cid, clip, pid, inplace, purpose) in enumerate(JOBS):
            a = ARM[cid]
            tag = f'{clip}_a{int(round(a * 100)):03d}'
            out = R / f'godot/animations/npc_activity_p10/{cid}/src/{tag}.fbx'
            if out.exists():
                print('skip (exists)', out.name); continue
            expr = f'{JS}({json.dumps(pid)},{json.dumps(CHAR[cid])},{json.dumps(inplace)},{a},{json.dumps(clip)})'
            await ws.send(json.dumps({'id': i + 1, 'method': 'Runtime.evaluate',
                                      'params': {'expression': expr, 'awaitPromise': True, 'returnByValue': True, 'timeout': 240000}}))
            while True:
                m = json.loads(await ws.recv())
                if m.get('id') == i + 1:
                    break
            res = m.get('result', {}).get('result', {}).get('value') or {'ok': False, 'err': str(m)[:300]}
            if not res.get('ok'):
                print('FAIL', cid, tag, res.get('err')); continue
            out.parent.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve(res.pop('url'), out)
            data = out.read_bytes()
            prov = {'character': cid, 'clip': tag, 'product': pid, 'arm_space': a, 'ok': True, 'job_uuid': res['job'],
                    'character_uuid': CHAR[cid], 'motion': res['motion'], 'raw_params': res['raw_params'], 'name': res['name'],
                    'supports_inplace': res['supports_inplace'], 'mixamo_frames': res['frames'], 'mixamo_duration': res['duration'],
                    'preferences': {'format': 'fbx7_2019', 'skin': 'false', 'fps': '30', 'reducekf': '0'}, 'purpose': purpose,
                    'file': str(out.relative_to(R)).replace('\\', '/'), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
            (PROV / f'{cid}_{tag}_download.json').write_text(json.dumps(prov, ensure_ascii=False, indent=2), encoding='utf-8')
            print('OK', cid, tag, res['name'], 'inplace', res['motion']['inplace'], len(data), 'bytes')


asyncio.run(main())
