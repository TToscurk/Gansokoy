"""Before/After pair sheet: python pair8.py <dir> <tagB> <tagA> <out> <names,comma> [tw]"""
import sys

from PIL import Image, ImageDraw, ImageFont

d, tb, ta, outp, names = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5].split(",")
tw = int(sys.argv[6]) if len(sys.argv) > 6 else 800
th = tw * 9 // 16
LAB = {
    "X03": "中橫街東端→稗田邸", "K01": "大宅門（南から）", "PA1": "中橫街の終点へ", "PA2": "辻から田埂道を南へ", "PA3": "田埂道を北へ（大宅門の道から）",
    "PA4": "辻の地蔵", "D02": "龍神橋の西から東望", "D03": "香霖堂口・東北巷", "D04": "東北南巷の奥", "PB1": "香霖堂口から集落へ",
    "PB2": "東北南巷", "PB3": "東北巷を南西へ戻る", "PB4": "龍神橋の上から集落",
}
font = ImageFont.truetype("C:/Windows/Fonts/msjh.ttc", 24)
sheet = Image.new("RGB", (2 * tw, len(names) * (th + 34)), (18, 18, 18))
dr = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    y = i * (th + 34)
    for j, t in enumerate((tb, ta)):
        im = Image.open(f"{d}/{t}_{n}.png").convert("RGB").resize((tw, th), Image.LANCZOS)
        sheet.paste(im, (j * tw, y + 34))
        dr.text((j * tw + 8, y + 4), f"{n} {LAB.get(n, '')}  {'BEFORE' if j == 0 else 'AFTER'}", fill=(255, 230, 120), font=font)
sheet.save(outp, quality=88)
print(outp, sheet.size)
