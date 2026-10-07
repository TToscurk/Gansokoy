"""R3c.1 motion GIFs: same review camera, R3b (left) vs R3c.1 (right), 24 frames at 4 fps (6 s), cropped
around the Sit / Carry / Talk residents of that camera and upscaled so the motion is reviewable.
Usage: uv run --with pillow python tools/gif_p10_r3c1_motion.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parents[1]
B = R / 'docs/art_review/village_v2_p10_population/activity_r1c1'
M, OUT = B / 'motion', B / 'review'
try:
    F = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 22)
except OSError:
    F = ImageFont.load_default()
# crop boxes from readability_baseline.json (feet / head pixels of the targeted residents in each camera)
CROPS = {
    '1_market_tps': ((1300, 560, 1900, 1000), 'M2 Talk（主婦・6 m）'),
    '2_market_west_tps': ((560, 360, 1060, 680), 'W4 Sit（藥草婆婆・縁台・10 m）／W3 Drink'),
    '3_main_street_tps': ((780, 400, 1040, 560), 'S2 Carry（八百屋・木箱）＋S3 Talk（19–20 m）'),
}
for view, (box, label) in CROPS.items():
    w = 640
    h = int(w * (box[3] - box[1]) / (box[2] - box[0]))
    frames = []
    for k in range(24):
        fr = Image.new('RGB', (w * 2, h + 34), '#202020')
        d = ImageDraw.Draw(fr)
        for i, mode in enumerate(['R3b', 'R3c1']):
            im = Image.open(M / f'{mode}__{view}__{k:02d}.jpg').crop(box).resize((w, h), Image.LANCZOS)
            fr.paste(im, (i * w, 34))
            d.text((i * w + 8, 6), ('R3b（activity off）' if mode == 'R3b' else 'R3c.1（activity on）') + '  ' + label, fill='white', font=F)
        frames.append(fr)
    out = OUT / f'motion_{view}_R3b_vs_R3c1.gif'
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=250, loop=0, optimize=True)
    print(out.name, frames[0].size, out.stat().st_size // 1024, 'KB')
