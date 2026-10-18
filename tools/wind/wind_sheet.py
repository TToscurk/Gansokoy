#!/usr/bin/env python3
"""把 wind_capture 的輸出做成審圖總表：
   每列一個機位，欄＝(breeze 第 1 幀, gust 第 1 幀, breeze 動量放大圖, gust 動量放大圖)。
用法：python tools/wind/wind_sheet.py --dir <capture out> --out <sheet.jpg> --views a,b,c
"""
import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

TILE_W = 460
PAD = 8
LABEL_H = 30


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--views", required=True)
    args = ap.parse_args()
    man = json.load(open(os.path.join(args.dir, "manifest.json"), encoding="utf-8"))
    by_key = {}
    for s in man["shots"]:
        by_key.setdefault(s["key"], []).append(s)
    rows = []
    for v in args.views.split(","):
        tiles = []
        for key in (f"{v}_breeze", f"{v}_gust"):
            shots = sorted(by_key.get(key, []), key=lambda s: s["frame"])
            if shots:
                tiles.append((f"{key} f0", Image.open(shots[0]["file"]).convert("RGB")))
        for pre in ("breeze", "gust"):
            diff = os.path.join(args.dir, f"diff_{v}_{pre}.jpg")
            if not os.path.exists(diff):
                diff = os.path.join(os.path.dirname(args.out), f"diff_{v}_{pre}.jpg")
            if os.path.exists(diff):
                tiles.append((f"{v} {pre} motion x14", Image.open(diff).convert("RGB")))
        if tiles:
            rows.append((v, tiles))
    if not rows:
        raise SystemExit("no tiles")
    h = int(TILE_W * 9 / 16)
    cols = max(len(t) for _, t in rows)
    W = cols * (TILE_W + PAD) + PAD
    H = len(rows) * (h + LABEL_H + PAD) + PAD
    sheet = Image.new("RGB", (W, H), (16, 16, 16))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 17)
    except OSError:
        font = ImageFont.load_default()
    for r, (vname, tiles) in enumerate(rows):
        y = PAD + r * (h + LABEL_H + PAD)
        for c, (label, im) in enumerate(tiles):
            x = PAD + c * (TILE_W + PAD)
            sheet.paste(im.resize((TILE_W, h), Image.LANCZOS), (x, y + LABEL_H))
            dr.text((x + 2, y + 5), label, fill=(235, 235, 215), font=font)
    sheet.save(args.out, quality=90)
    print("sheet ->", args.out, sheet.size)


if __name__ == "__main__":
    main()
