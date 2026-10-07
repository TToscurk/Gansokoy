"""R3c W3 Drink A/B — comparison sheets from shot_p10_drink_ab.gd renders (rows = candidates, cols = moments).
Usage: uv run --with pillow python tools/sheet_p10_drink_ab.py
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parents[1]
D = R / 'docs/art_review/village_v2_p10_population/activity_r1/drink_ab/render'
rows = json.loads((D / 'capture.json').read_text(encoding='utf-8'))
cands = list(dict.fromkeys(r['candidate'] for r in rows))
views = list(dict.fromkeys(r['view'] for r in rows))
moments = ['hold', 'approach', 'sip', 'widest', 'return']
try:
    font = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 26)
except OSError:
    font = ImageFont.load_default()
for v in views:
    vr = [r for r in rows if r['view'] == v]
    ms = [m for m in moments if any(r['moment'] == m for r in vr)]
    close = v.startswith('close')
    crop = (560, 0, 1360, 1080) if close else (240, 0, 1680, 1080)
    tw = 520 if close else 700
    th = int(tw * (crop[3] - crop[1]) / (crop[2] - crop[0]))
    sheet = Image.new('RGB', (200 + tw * len(ms), 50 + th * len(cands)), '#202020')
    dr = ImageDraw.Draw(sheet)
    for j, m in enumerate(ms):
        dr.text((200 + j * tw + 8, 10), m, fill='white', font=font)
    for i, c in enumerate(cands):
        dr.text((8, 50 + i * th + th // 2 - 30), c.replace('_', '\n', 1), fill='white', font=font)
        for j, m in enumerate(ms):
            r = next((x for x in vr if x['candidate'] == c and x['moment'] == m), None)
            if not r:
                continue
            im = Image.open(D / r['file']).crop(crop).resize((tw, th))
            sheet.paste(im, (200 + j * tw, 50 + i * th))
            dr.text((200 + j * tw + 6, 50 + i * th + th - 34), 't=%.2fs' % r['time'], fill='yellow', font=font)
    out = D.parent / f'drink_ab_{v}.jpg'
    sheet.save(out, quality=88)
    print(out.name, sheet.size)
