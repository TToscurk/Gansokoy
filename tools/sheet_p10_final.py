"""P10 FINAL 統合走訪の審圖シート（walk_p10_final.gd の出力から）。
Usage: uv run --with pillow python tools/sheet_p10_final.py <run_dir> <out_dir>
  stills_all.jpg        12 枚の TPS still（4×3）
  stills_<a>.jpg        still を 2×2 ずつ（大きめ、vision 用）
  seg_<name>.jpg        区間ごとに等間隔 12 コマ（4×3、時刻つき）
  armpull.jpg           SpringArm が縮んだ瞬間（ARM_PULL）の前後コマ
"""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

RUN = Path(sys.argv[1])
OUT = Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)
L = json.loads((RUN / 'walk_log.json').read_text(encoding='utf-8'))
try:
    F = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 20)
except OSError:
    F = ImageFont.load_default()


def label(d, xy, t):
    w = d.textlength(t, font=F)
    d.rectangle([xy[0], xy[1], xy[0] + w + 12, xy[1] + 28], fill=(0, 0, 0))
    d.text((xy[0] + 6, xy[1] + 3), t, fill=(255, 230, 80), font=F)


def grid(items, cols, w, path):
    ims = []
    for im_path, text in items:
        im = Image.open(im_path).convert('RGB')
        im = im.resize((w, int(im.height * w / im.width)))
        ims.append((im, text))
    h = ims[0][0].height
    rows = (len(ims) + cols - 1) // cols
    sh = Image.new('RGB', (w * cols + 4 * (cols - 1), h * rows + 4 * (rows - 1)), (16, 16, 16))
    d = ImageDraw.Draw(sh)
    for i, (im, text) in enumerate(ims):
        x, y = (i % cols) * (w + 4), (i // cols) * (h + 4)
        sh.paste(im, (x, y))
        label(d, (x + 6, y + 6), text)
    sh.save(path, quality=88)


st = L['stills']
grid([(RUN / 'stills' / f"{s['name']}.png", f"{s['name']}  NPC≤25m {s['npc_within_25m']}") for s in st], 4, 640, OUT / 'stills_all.jpg')
for k in range(0, len(st), 4):
    grid([(RUN / 'stills' / f"{s['name']}.png", s['name']) for s in st[k:k + 4]], 2, 960, OUT / f'stills_{k // 4 + 1}.jpg')
t0 = 0.0
starts = {}
for s in L['segments']:
    starts[s['name']] = t0
    t0 += float(s.get('seconds', 0.0))
for s in L['segments']:
    if not s['rec']:
        continue
    n = int(s['frames'])
    idx = [round(i * (n - 1) / 11) for i in range(12)]
    grid([(RUN / 'frames' / s['name'] / f'{i:05d}.jpg', f"{s['name']} t+{i / 10:.1f}s") for i in idx], 4, 480, OUT / f"seg_{s['name']}.jpg")
ap = []
for e in L['events']:
    if e['kind'] != 'ARM_PULL':
        continue
    i = int(round((float(e['t']) - starts[e['seg']]) * 10))
    n = next(int(s['frames']) for s in L['segments'] if s['name'] == e['seg'])
    for j in (i - 5, i, i + 5):
        j = max(0, min(n - 1, j))
        ap.append((RUN / 'frames' / e['seg'] / f'{j:05d}.jpg', f"{e['seg']} t{e['t']} arm {e['hit_length']} f{j}"))
if ap:
    grid(ap, 3, 480, OUT / 'armpull.jpg')
print('sheets →', OUT)
