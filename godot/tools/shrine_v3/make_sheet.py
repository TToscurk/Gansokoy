"""把一個資料夾的 PNG 截圖拼成一張總表（2 欄），每張下方標檔名。
  python tools/shrine_v3/make_sheet.py <資料夾> <輸出.jpg> [欄數=2] [寬=800]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def main():
    src = sys.argv[1]
    out = sys.argv[2]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    w = int(sys.argv[4]) if len(sys.argv) > 4 else 800
    files = sorted(f for f in os.listdir(src) if f.lower().endswith('.png'))
    if not files:
        print('no png')
        return
    ims = [Image.open(os.path.join(src, f)).convert('RGB') for f in files]
    h = int(ims[0].height * w / ims[0].width)
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * w, rows * (h + 26)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    f = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 18)
    for i, (im, fn) in enumerate(zip(ims, files)):
        x = (i % cols) * w
        y = (i // cols) * (h + 26)
        sheet.paste(im.resize((w, h), Image.LANCZOS), (x, y))
        dr.text((x + 6, y + h + 2), fn[:-4], fill=(255, 255, 255), font=f)
    sheet.save(out, quality=88)
    print(out, sheet.size)


if __name__ == '__main__':
    main()
