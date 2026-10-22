"""植被多樣性：修正前／後同角度對照（每列左＝修正前、右＝修正後）。
  python tools/shrine_v3/compare_div.py <before_dir> <after_dir> <out_prefix>
輸出 <out_prefix>_A.jpg（石段、鳥居、神社正面／側面）與 <out_prefix>_B.jpg（櫻林、池塘、西望、鳥瞰、東側鎮守之森）。
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SHOTS = [
    ('D01_stair_up', '石段腳往上看'), ('D02_stair_mid', '石段中段往上看'), ('D03_torii_front', '鳥居（石段頂往前庭）'),
    ('D04_torii_back', '鳥居往南外望（南坡林）'), ('D05_court_front', '神社正面'), ('D06_haiden_side', '神社側面'),
    ('D07_back_grove', '櫻花林（拜殿後）'), ('D08_grove_ground', '櫻花林與林床'), ('D09_pond', '池塘周圍'),
    ('D10_court_outlook_west', '前庭往西南看（西坡林）'), ('D11_aerial', '整體鳥瞰'), ('D12_east_forest', '東側鎮守之森（俯瞰）'),
]
W, H = 720, 405


def font(sz):
    for f in ['C:/Windows/Fonts/msjh.ttc', 'C:/Windows/Fonts/mingliu.ttc']:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def sheet(bdir, adir, items, out):
    f1, f2 = font(24), font(20)
    im = Image.new('RGB', (W * 2 + 18, len(items) * (H + 38) + 10), (24, 24, 24))
    d = ImageDraw.Draw(im)
    for i, (n, label) in enumerate(items):
        y = i * (H + 38) + 10
        d.text((8, y), label, font=f1, fill=(235, 235, 235))
        for j, (lab, dd, col) in enumerate((('修正前', bdir, (210, 130, 130)), ('修正後', adir, (130, 210, 150)))):
            x = 6 + j * (W + 6)
            p = os.path.join(dd, n + '.png')
            if os.path.exists(p):
                im.paste(Image.open(p).convert('RGB').resize((W, H)), (x, y + 32))
            d.rectangle([x, y + 32, x + 84, y + 62], fill=(0, 0, 0))
            d.text((x + 8, y + 34), lab, font=f2, fill=col)
    im.save(out, quality=86)
    print('[SHEET]', out, im.size)


if __name__ == '__main__':
    b, a, o = sys.argv[1:4]
    sheet(b, a, SHOTS[:6], o + '_A.jpg')
    sheet(b, a, SHOTS[6:], o + '_B.jpg')
