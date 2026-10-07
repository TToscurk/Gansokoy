"""R3c.1 candidate sheets: rows = candidates (R3b first), cols = 6 phases; one sheet per actor × camera.
Review-camera crops are centred on the actor's projected feet/head (activity_r1c1/readability_baseline.json,
same camera solve); the tps6m camera looks straight at the actor, so it is centre-cropped.
Usage: uv run --with pillow python tools/sheet_p10_r3c1.py [render_dir_name]
"""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parents[1]
B = R / 'docs/art_review/village_v2_p10_population/activity_r1c1'
D = B / (sys.argv[1] if len(sys.argv) > 1 else 'candidates_render')
rows = json.loads((D / 'capture.json').read_text(encoding='utf-8'))
base = json.loads((B / 'readability_baseline.json').read_text(encoding='utf-8'))
try:
    F = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 22)
except OSError:
    F = ImageFont.load_default()
groups = {}
for r in rows:
    groups.setdefault((r['actor'], r['view']), []).append(r)
for (actor, view), rs in groups.items():
    if view == 'tps6m':
        box = (660, 140, 1260, 1040)
    else:
        a = next(x for x in base[view]['actors'] if x['actor'] == actor)
        fx, fy = a['feet_px']; h = max(a['height_px'], 50)
        box = (fx - int(h * 0.9), fy - int(h * 1.45), fx + int(h * 0.9), fy + int(h * 0.25))
    cands = list(dict.fromkeys(r['clip'] for r in rs))
    tw = 300; th = int(tw * (box[3] - box[1]) / (box[2] - box[0]))
    sheet = Image.new('RGB', (230 + tw * 6, th * len(cands)), '#202020')
    dr = ImageDraw.Draw(sheet)
    for i, c in enumerate(cands):
        dr.text((6, i * th + th // 2 - 12), c or 'R3b baseline', fill='white', font=F)
        for r in [x for x in rs if x['clip'] == c]:
            im = Image.open(D / r['file']).crop(box).resize((tw, th))
            sheet.paste(im, (230 + r['phase'] * tw, i * th))
    name = f"{actor.split('/')[-1]}__{view}.jpg"
    sheet.save(D.parent / ('sheet_' + name), quality=88)
    print(name, sheet.size, 'crop', box)
