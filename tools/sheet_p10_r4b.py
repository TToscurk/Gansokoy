"""P10 R4b Human-Use Expansion Batch 1 審圖シート（human_use_exp_b1/render → review）。
Usage: uv run --with pillow python tools/sheet_p10_r4b.py
  群ごと 1 枚：行＝near（相機 5–10 m）／mid（10–15 m）／high（俯瞰）、列＝BEFORE（擴張なし・NPC あり）／AFTER（擴張・NPC あり）／NPC OFF（擴張・NPC なし）。
  區ごと 1 枚：near の NPC OFF だけを並べた一覧（區の中で重複・平均化していないかを見る）。
  npc_on_off.jpg：NPC が実際に立つ所から群を見た実際の遊戲（AFTER）と NPC OFF。
  distribution.jpg：村の真上（3 px/m）に R4 Pilot（封存・青）と R4b（橙、群 ID）の位置、BEFORE（R4b なし）と並べる。
  計画の座標：$TMPDIR/r4b/plan_r3.json（verify --dump）と data/village_v2_p10r4_snapshot.json。
"""
import os
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
B = ROOT / 'docs/art_review/village_v2_p10_props/human_use_exp_b1'
R = B / 'render'
O = B / 'review'
views = json.loads((ROOT / 'godot/tools/shot_p10_human_use_exp_views.json').read_text(encoding='utf-8'))
try:
    F = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 22)
except OSError:
    F = ImageFont.load_default()
W = 640
ST = [('before', 'BEFORE'), ('after', 'AFTER'), ('npcoff', 'NPC OFF')]


def load(p, w=W):
    im = Image.open(p).convert('RGB')
    return im.resize((w, int(im.height * w / im.width)))


def label(d, xy, t):
    d.rectangle([xy[0], xy[1], xy[0] + 12 * len(t) + 18, xy[1] + 30], fill=(0, 0, 0))
    d.text((xy[0] + 6, xy[1] + 3), t, fill=(255, 230, 80), font=F)


cls = []
for v in views:
    if v[0].endswith('_npc'):
        continue
    c = v[0].rsplit('_', 1)[0]
    if c not in cls:
        cls.append(c)
O.mkdir(parents=True, exist_ok=True)
for c in cls:
    rows = []
    for band in ('near', 'mid', 'high'):
        if (R / f'{c}_{band}_after.png').exists():
            rows.append((band, [load(R / f'{c}_{band}_{s}.png') for s, _ in ST]))
    H = rows[0][1][0].height
    sh = Image.new('RGB', (W * 3, (H + 4) * len(rows)), (16, 16, 16))
    d = ImageDraw.Draw(sh)
    for r, (band, ims) in enumerate(rows):
        for k, im in enumerate(ims):
            sh.paste(im, (k * W, r * (H + 4)))
            label(d, (k * W + 6, r * (H + 4) + 6), f'{c} {band} {ST[k][1]}')
    sh.save(O / f'{c}.jpg', quality=88)
for z in 'ABC':
    zc = [c for c in cls if c.startswith('X' + z)]
    ims = [load(R / f'{c}_near_npcoff.png', 800) for c in zc]
    H = ims[0].height
    n = len(ims)
    cols = 2 if n <= 4 else 3
    rws = (n + cols - 1) // cols
    sh = Image.new('RGB', (800 * cols, (H + 4) * rws), (16, 16, 16))
    d = ImageDraw.Draw(sh)
    for i, (c, im) in enumerate(zip(zc, ims)):
        x, y = (i % cols) * 800, (i // cols) * (H + 4)
        sh.paste(im, (x, y))
        label(d, (x + 6, y + 6), f'{c} near NPC OFF')
    sh.save(O / f'zone{z}_overview_npcoff.jpg', quality=88)
print('sheets →', O, len(cls), 'clusters')

# NPC ON／OFF（実際の遊戲：NPC の立つ所から）
npcv = [v[0] for v in views if v[0].endswith('_npc')]
if npcv:
    ims = [[load(R / f'{n}_{s}.png', 800) for s in ('after', 'npcoff')] for n in npcv]
    H = ims[0][0].height
    sh = Image.new('RGB', (1600, (H + 4) * len(npcv)), (16, 16, 16))
    d = ImageDraw.Draw(sh)
    for r, (n, pair) in enumerate(zip(npcv, ims)):
        for k, im in enumerate(pair):
            sh.paste(im, (k * 800, r * (H + 4)))
            label(d, (k * 800 + 6, r * (H + 4) + 6), f'{n} {"AFTER (NPC ON, game)" if k == 0 else "NPC OFF"}')
    sh.save(O / 'npc_on_off.jpg', quality=88)
# 分布図
X0, Z0, PPM = 130.0, -245.0, 3.0
plan = json.loads(Path(os.environ.get('TMPDIR', 'C:/Users/B365/AppData/Local/hermes/cache/scratch') + '/r4b/plan_r3.json').read_text(encoding='utf-8'))
snap = json.loads((ROOT / 'godot/data/village_v2_p10r4_snapshot.json').read_text(encoding='utf-8'))
if (R / 'top_village_after.png').exists():
    pair = []
    for st in ('before', 'after'):
        im = Image.open(R / f'top_village_{st}.png').convert('RGB')
        d = ImageDraw.Draw(im)
        r4c = {}
        for it in snap['items']:
            r4c.setdefault(it['cluster'], []).append((it['position'][0], it['position'][2]))
        for k, pts in r4c.items():
            x = sum(p[0] for p in pts) / len(pts)
            z = sum(p[1] for p in pts) / len(pts)
            u, w = (x - X0) * PPM, (z - Z0) * PPM
            d.ellipse([u - 9, w - 9, u + 9, w + 9], outline=(80, 170, 255), width=3)
        if st == 'after':
            for c in plan['clusters']:
                u, w = (c['center'][0] - X0) * PPM, (c['center'][1] - Z0) * PPM
                d.ellipse([u - 11, w - 11, u + 11, w + 11], outline=(255, 150, 30), width=4)
                d.rectangle([u + 12, w - 12, u + 12 + 13 * len(c['id'][:3]) + 8, w + 14], fill=(0, 0, 0))
                d.text((u + 16, w - 11), c['id'][:3], fill=(255, 190, 80), font=F)
        label(d, (8, 8), 'BEFORE (R4 sealed = blue)' if st == 'before' else 'AFTER R4b batch 1 (orange) + R4 (blue)')
        pair.append(im)
    sh = Image.new('RGB', (pair[0].width * 2 + 6, pair[0].height), (16, 16, 16))
    sh.paste(pair[0], (0, 0))
    sh.paste(pair[1], (pair[0].width + 6, 0))
    sh.save(O / 'distribution.jpg', quality=88)
print('extra sheets: npc', len(npcv), 'distribution', (R / 'top_village_after.png').exists())
