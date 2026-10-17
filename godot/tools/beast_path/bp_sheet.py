#!/usr/bin/env python
"""獸道：把一個資料夾的審圖 PNG 拼成一張總表（每格附檔名），供 bp_iterate.sh 用。
  python godot/tools/beast_path/bp_sheet.py <in_dir> <out.jpg> [--cols=4] [--w=480]
"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opt = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    src, out = args[0], args[1]
    cols, w = int(opt.get('cols', 4)), int(opt.get('w', 480))
    files = sorted(f for f in glob.glob(os.path.join(src, '*.png')) if '__h' not in os.path.basename(f))
    if not files:
        sys.exit('[BP_SHEET] 沒有 PNG：%s' % src)
    ims = [Image.open(f).convert('RGB') for f in files]
    h = int(w * ims[0].height / ims[0].width)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * w, rows * (h + 22)), (24, 24, 24))
    try:
        font = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 16)
    except OSError:
        font = ImageFont.load_default()
    d = ImageDraw.Draw(sheet)
    for i, (f, im) in enumerate(zip(files, ims)):
        x, y = (i % cols) * w, (i // cols) * (h + 22)
        sheet.paste(im.resize((w, h)), (x, y + 22))
        d.text((x + 6, y + 3), os.path.splitext(os.path.basename(f))[0], fill=(230, 230, 230), font=font)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out, quality=85)
    print('[BP_SHEET] %d 張 → %s' % (len(ims), out))


if __name__ == '__main__':
    main()
