"""博麗神社 v3：程序生成的小貼圖（扁額、社號標刻字、鈴緒條紋）。輸出 assets/shrine_v3/tex/gen/。
  python tools/shrine_v3/make_gen_textures.py
字型：標楷體 C:/Windows/Fonts/kaiu.ttf（系統字型，只用來把字畫進貼圖；不散佈字型檔）。
"""
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(GODOT, 'assets', 'shrine_v3', 'tex', 'gen')
PH = os.path.join(GODOT, 'assets', 'shrine_v3', 'tex', 'ph')
os.makedirs(OUT, exist_ok=True)
KAI = 'C:/Windows/Fonts/kaiu.ttf'
TEXT = '博麗神社'


def vertical_text(draw, box, text, font, fill):
    x0, y0, x1, y1 = box
    n = len(text)
    h = (y1 - y0) / n
    for i, ch in enumerate(text):
        bb = draw.textbbox((0, 0), ch, font=font)
        w = bb[2] - bb[0]
        hh = bb[3] - bb[1]
        cx = (x0 + x1) / 2 - w / 2 - bb[0]
        cy = y0 + h * i + h / 2 - hh / 2 - bb[1]
        draw.text((cx, cy), ch, font=font, fill=fill)


def plaque():
    W, H = 288, 412   # 0.42 × 0.60 m
    S = 3
    im = Image.new('RGB', (W * S, H * S), (16, 13, 11))
    d = ImageDraw.Draw(im)
    # 金框
    m = 10 * S
    d.rectangle([m, m, W * S - m, H * S - m], outline=(150, 118, 58), width=7 * S)
    d.rectangle([m + 12 * S, m + 12 * S, W * S - m - 12 * S, H * S - m - 12 * S], outline=(96, 76, 40), width=2 * S)
    f = ImageFont.truetype(KAI, 82 * S)
    vertical_text(d, (0, 34 * S, W * S, H * S - 30 * S), TEXT, f, (206, 172, 92))
    im = im.resize((W, H), Image.LANCZOS)
    # 舊化：金字剝落、黑漆斑駁
    a = np.asarray(im).astype(np.float32)
    rng = np.random.default_rng(3)
    n = rng.random((H, W))
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2))).astype(np.float32) / 255.0
    gold = (a[..., 0] > 90)[..., None]
    a = np.where(gold, a * (0.70 + 0.45 * n[..., None]), a * (0.85 + 0.3 * n[..., None]))
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, 'plaque_hakurei.png'))


def stone_text():
    W, H = 160, 940   # 0.24 × 1.40 m
    src = Image.open(os.path.join(PH, 'rock_boulder_dry_diff_2k.jpg')).convert('RGB')
    base = src.crop((300, 200, 300 + W * 2, 200 + H * 2)).resize((W, H), Image.LANCZOS)
    a = np.asarray(base).astype(np.float32)
    # 刻字遮罩
    S = 3
    m = Image.new('L', (W * S, H * S), 0)
    d = ImageDraw.Draw(m)
    f = ImageFont.truetype(KAI, 118 * S)
    vertical_text(d, (0, 40 * S, W * S, H * S - 40 * S), TEXT, f, 255)
    m = m.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8))
    mk = np.asarray(m).astype(np.float32)[..., None] / 255.0
    # 刻痕：暗、邊緣下緣略亮（受光）
    sh = np.roll(mk, -2, axis=0)
    a = a * (1.0 - 0.62 * mk) + 26.0 * np.clip(mk - sh, 0, 1)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, 'stone_text_hakurei.png'))


def rope_rw():
    W, H = 64, 256
    im = Image.new('RGB', (W, H), (230, 226, 214))
    d = ImageDraw.Draw(im)
    for k in range(-8, 16):
        y = k * 32
        d.polygon([(0, y), (W, y - 26), (W, y - 10), (0, y + 16)], fill=(150, 34, 30))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    im.save(os.path.join(OUT, 'rope_rw.png'))


if __name__ == '__main__':
    plaque()
    stone_text()
    rope_rw()
    print('[gen-tex] ->', OUT, sorted(os.listdir(OUT)))
