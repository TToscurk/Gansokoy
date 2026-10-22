"""博麗神社 v3 美術深化：修正前／後同角度對照表（Pillow）。
  python compare_sheet.py <before_dir> <after_dir> <out_prefix>
輸出 <out_prefix>_A.jpg（p01–p06）、<out_prefix>_B.jpg（p07–p12）：每列左＝修正前、右＝修正後。
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

NAMES = {
    'p01_stair_up': '1 石階往上看（階腳）',
    'p02_stair_mid': '1b 石階中段（側看兩側植被）',
    'p03_stair_down': '1c 石階頂往下看',
    'p04_torii_front': '2 鳥居前（外→內）',
    'p05_torii_back': '2b 鳥居後（內→外）',
    'p06_court_front': '3 前庭正面',
    'p07_sando_haiden': '4 主參道→拜殿',
    'p08_temizuya': '5 手水舍',
    'p09_haiden_close': '6 拜殿正面近景',
    'p10_storehouse': '7 倉庫側',
    'p11_court_oblique': '3b 前庭斜俯瞰',
    'p12_aerial': '8 整體鳥瞰',
}
W = 800
H = 450
PAD = 6
HEAD = 34


def font(sz):
    for p in ('C:/Windows/Fonts/msjhbd.ttc', 'C:/Windows/Fonts/msjh.ttc', 'C:/Windows/Fonts/kaiu.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def main():
    bdir, adir, outp = sys.argv[1], sys.argv[2], sys.argv[3]
    keys = list(NAMES.keys())
    f1 = font(22)
    f2 = font(18)
    for part, ks in (('A', keys[:6]), ('B', keys[6:])):
        rows = [k for k in ks if os.path.exists(os.path.join(bdir, k + '.png')) and os.path.exists(os.path.join(adir, k + '.png'))]
        sheet = Image.new('RGB', (W * 2 + PAD * 3, (H + HEAD + PAD) * len(rows) + PAD), (24, 24, 26))
        d = ImageDraw.Draw(sheet)
        for i, k in enumerate(rows):
            y = PAD + i * (H + HEAD + PAD)
            d.text((PAD + 4, y + 4), NAMES[k] + '　' + k, font=f1, fill=(235, 235, 235))
            for j, (lab, dd, col) in enumerate((('修正前', bdir, (200, 120, 120)), ('修正後', adir, (120, 200, 140)))):
                im = Image.open(os.path.join(dd, k + '.png')).convert('RGB').resize((W, H), Image.LANCZOS)
                x = PAD + j * (W + PAD)
                sheet.paste(im, (x, y + HEAD))
                d.rectangle((x, y + HEAD, x + 92, y + HEAD + 30), fill=(0, 0, 0))
                d.text((x + 8, y + HEAD + 3), lab, font=f2, fill=col)
        out = '%s_%s.jpg' % (outp, part)
        sheet.save(out, quality=86)
        print('[SHEET]', out, sheet.size, len(rows), 'rows')


if __name__ == '__main__':
    main()
