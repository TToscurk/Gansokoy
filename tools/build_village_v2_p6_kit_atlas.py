#!/usr/bin/env python3
"""人間之里 V2 P6 R1／R2：模組化町家 Kit atlas 產生器（R2 Variation Pass 在未用區加變體圖塊，R1 圖塊不動）。

  python tools/build_village_v2_p6_kit_atlas.py

沿用 build_village_v2_r6_atlas.py 的結構（build_village_v2_r2_atlases.py 的 _write／_swatches／_emit_box、
build_village_v2_textures.py 的 _paper／_wood_patch／_cloth）；不重建共享材質庫與 R1–R6 atlas。
輸出：godot/assets/village_v2/machiya_kit/{machiya_kit_atlas.png, machiya_kit_emit.png, atlas.json, V2_MachiyaKit.tres}。
參考（vision brief，docs/reference/民宅/）：普町1／普町2／普町3／普町4／商家／長屋——
  深褐風化木構、米白灰泥、千本格子（淺紙背）、蟲籠窓、二樓格子窓、雨戶、腰板、灰瓦；
  商家＝開放店先＋暖簾＋無字看板。暖簾／看板一律只用幾何家紋，**不寫字**（額牌文字不清楚的版本不定稿）。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_village_v2_textures as T  # noqa: E402
import build_village_v2_r2_atlases as A  # noqa: E402

SIZE = A.SIZE   # 2048

# 像素（x0, y0, x1, y1），原點左上
REGIONS = {
    'koshi': (0, 0, 512, 512),              # 1F 千本格子（淺紙背、下 16 % 腰板）
    'mushiko': (512, 0, 1024, 256),         # 厨子二階 蟲籠窓（灰泥＋縱塗格子）
    'mado': (512, 256, 1024, 512),          # 小窓（平屋高窓、側窓）：竹格子＋紙
    'window_2f': (1024, 0, 1536, 512),      # 總二階 2F 格子窓
    'shoji': (1536, 0, 2048, 512),          # 障子（背面、側面）
    'door': (0, 512, 512, 1024),            # 格子引戶（上格子、下板）
    'shop_in': (512, 512, 1024, 1024),      # 店先內：暗店內＋貨架（壺、反物、籠）
    'amado': (1024, 512, 1536, 768),        # 雨戶（縱板＋橫桟）
    'tsuma': (1024, 768, 1536, 1024),       # 妻面：灰泥＋露明木構
    'noren_a': (1536, 512, 2048, 768),      # 暖簾 藍（3 幅、白抜き丸紋）
    'noren_b': (1536, 768, 2048, 1024),     # 暖簾 茶（3 幅、白抜き菱紋）
    'sudare': (0, 1024, 512, 1280),         # 簾（竹）
    'kanban': (512, 1024, 1024, 1280),      # 看板（無字；木框＋家紋）
    'noren_c': (0, 1280, 512, 1536),        # 暖簾 鼠（2 幅、白抜き井桁）
    'goods': (512, 1280, 1024, 1536),       # 店頭台上商品（籠、俵、壺）正面
    'mushiko_b': (1024, 1024, 1536, 1280),  # R2：蟲籠窓 變體（土壁色、粗格子）
    'sudare_b': (1024, 1280, 1536, 1536),   # R2：簾 變體（舊竹、上捲）
    'swatch': (1536, 1024, 2048, 1280),
    'koshi_b': (1536, 1280, 2048, 1536),    # 1F 格子 變體（粗格子＝米屋格子、暗紙背）
    # ── P6 R2 Variation Pass（原未用的第 4 列 y 1536–2048）──
    'koshi_r': (0, 1536, 512, 2048),        # 弁柄格子（紅褐、細密、淺紙背）
    'noren_d': (512, 1536, 1024, 1792),     # 暖簾 生成（米白 2 幅、藍 亀甲）
    'noren_e': (512, 1792, 1024, 2048),     # 暖簾 弁柄（4 幅短、白 菱）
    'kanban_b': (1024, 1536, 1536, 1792),   # 看板 黑漆＋金 亀甲（無字）
    'kanban_c': (1024, 1792, 1536, 2048),   # 看板 白木＋墨 菱（無字）
    'window_b': (1536, 1536, 2048, 2048),   # 2F 窓 變體：弁柄粗格子＋障子
}
SW = ['#2E2119', '#4A3526', '#E8E0CF', '#6B6F70', '#8C7A5A', '#3B3F40', '#9A7B55', '#C9BFA8']
SW_NOTE = ['深褐（木構暗部）', '褐（格子）', '米白（灰泥）', '瓦邊灰', '古銅（金具）', '暗灰（瓦影）', '淺褐（新木）', '紙色']


def _crest(d, cx, cy, r, kind, fill):
    """幾何家紋（不含文字）。"""
    w = max(3, r // 7)
    if kind == 'janome':     # 蛇の目（同心圓）
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=fill, width=w * 2)
        d.ellipse((cx - r * 0.35, cy - r * 0.35, cx + r * 0.35, cy + r * 0.35), fill=fill)
    elif kind == 'hishi':    # 菱
        d.polygon([(cx, cy - r), (cx + r * 0.8, cy), (cx, cy + r), (cx - r * 0.8, cy)], outline=fill, width=w)
        d.polygon([(cx, cy - r * 0.45), (cx + r * 0.36, cy), (cx, cy + r * 0.45), (cx - r * 0.36, cy)], fill=fill)
    else:                    # 亀甲（六角）
        import math as _m
        for k, rr in ((0, r), (1, r * 0.5)):
            pts = [(cx + rr * _m.cos(_m.pi / 3 * i), cy + rr * _m.sin(_m.pi / 3 * i)) for i in range(6)]
            if k == 0:
                d.polygon(pts, outline=fill, width=w)
            else:
                d.polygon(pts, fill=fill)


def _noren(w, h, color, panels, crest, seed):
    img = T._cloth(w, h, color, seed)
    d = ImageDraw.Draw(img)
    pw = w / panels
    for i in range(panels):
        x0 = int(i * pw)
        if i:
            d.rectangle((x0 - 3, int(h * 0.10), x0 + 3, h), fill=(20, 18, 16))   # 幅と幅の切れ目（暗）
        _crest(d, int(x0 + pw / 2), int(h * 0.52), int(min(pw, h) * 0.26), crest, (226, 220, 204))
    d.rectangle((0, 0, w, int(h * 0.10)), fill=tuple(int(c * 0.55) for c in A._hex255(color)))   # 竿袋
    return img


def build():
    atlas = Image.new('RGB', (SIZE, SIZE), (36, 30, 26))
    emit = Image.new('RGB', (SIZE // 4, SIZE // 4), (0, 0, 0))
    R = REGIONS
    frame, bar = A._hex255('#2E2119'), A._hex255('#4A3526')

    def sz(k):
        x0, y0, x1, y1 = R[k]
        return x1 - x0, y1 - y0

    # 千本格子：縱格子密排、淺紙背，下 16 % 腰板
    for key, tone, pitch, bw, seed in (('koshi', '#CFC4AE', 22, 11, 701), ('koshi_b', '#8E8474', 34, 16, 702)):
        w, h = sz(key)
        kc = T._paper(w, h, seed, tone=tone)
        d = ImageDraw.Draw(kc)
        kh = int(h * 0.84)
        for x in range(6, w, pitch):
            d.rectangle((x, 0, x + bw, kh), fill=bar)
        for y in (int(h * 0.30), int(h * 0.60)):
            d.rectangle((0, y, w, y + 8), fill=frame)
        kc.paste(T._wood_patch(w, h - kh, '#4E3A2A', seed + 10), (0, kh))
        d.rectangle((0, kh - 8, w, kh), fill=frame)
        d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=14)
        atlas.paste(kc, R[key][:2])
    # 蟲籠窓：灰泥面上一排縱塗格子（深灰泥色）
    w, h = sz('mushiko')
    mk = T._paper(w, h, 703, tone='#DCD3C0')
    d = ImageDraw.Draw(mk)
    d.rectangle((22, 38, w - 23, h - 39), fill=A._hex255('#2B241E'))
    for x in range(30, w - 30, 30):
        d.rectangle((x, 38, x + 15, h - 39), fill=A._hex255('#BDB3A0'))
    d.rectangle((22, 38, w - 23, h - 39), outline=A._hex255('#A89E8A'), width=8)
    atlas.paste(mk, R['mushiko'][:2])
    # 小窓：竹格子＋紙
    w, h = sz('mado')
    md = T._paper(w, h, 704, tone='#D9CFB8')
    d = ImageDraw.Draw(md)
    for x in range(10, w, 36):
        d.rectangle((x, 0, x + 12, h), fill=A._hex255('#6B5A3A'))
    d.rectangle((0, h // 2 - 5, w, h // 2 + 5), fill=frame)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=16)
    atlas.paste(md, R['mado'][:2])
    # 2F 格子窓：外框＋細縱格子（紙背微暖）
    w, h = sz('window_2f')
    wn = T._paper(w, h, 705, tone='#D9CFB8')
    d = ImageDraw.Draw(wn)
    for x in range(0, w, 26):
        d.rectangle((x, 0, x + 9, h), fill=bar)
    for y in (h // 3, 2 * h // 3):
        d.rectangle((0, y, w, y + 8), fill=bar)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=22)
    d.line((w // 2, 0, w // 2, h), fill=frame, width=12)
    atlas.paste(wn, R['window_2f'][:2])
    # 障子
    w, h = sz('shoji')
    sj = T._paper(w, h, 706, tone='#E3DCCB')
    d = ImageDraw.Draw(sj)
    for x in range(0, w, 64):
        d.rectangle((x, 0, x + 5, h), fill=A._hex255('#5A4432'))
    for y in range(0, h, 96):
        d.rectangle((0, y, w, y + 5), fill=A._hex255('#5A4432'))
    d.rectangle((0, int(h * 0.80), w, h), fill=A._hex255('#5A4432'))
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=16)
    atlas.paste(sj, R['shoji'][:2])
    # 格子引戶：上 60 % 格子（暗紙背）、下板
    w, h = sz('door')
    dr = T._wood_patch(w, h, '#4E3A2A', 707)
    d = ImageDraw.Draw(dr)
    d.rectangle((20, 20, w - 21, int(h * 0.60)), fill=A._hex255('#8C8270'))
    for x in range(20, w - 20, 24):
        d.rectangle((x, 20, x + 9, int(h * 0.60)), fill=bar)
    for y in range(20, int(h * 0.60), 64):
        d.rectangle((20, y, w - 21, y + 7), fill=bar)
    d.rectangle((0, int(h * 0.60), w, int(h * 0.64)), fill=frame)
    for x in range(0, w, 64):
        d.line((x, int(h * 0.64), x, h), fill=A._hex255('#3A2A1E'), width=3)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=20)
    d.line((w // 2, 0, w // 2, h), fill=frame, width=14)
    atlas.paste(dr, R['door'][:2])
    # 店先內：暗店內、三層貨架＋壺／反物／籠（剪影）
    w, h = sz('shop_in')
    si = Image.new('RGB', (w, h), (30, 24, 19))
    d = ImageDraw.Draw(si)
    rng = np.random.default_rng(708)
    for k, y in enumerate((int(h * 0.30), int(h * 0.55), int(h * 0.80))):
        d.rectangle((0, y, w, y + 10), fill=(70, 52, 36))
        x = 12
        while x < w - 40:
            gw = int(rng.integers(26, 64))
            gh = int(rng.integers(30, 80))
            col = [(120, 96, 64), (88, 72, 58), (140, 120, 92), (72, 84, 96), (110, 70, 52)][int(rng.integers(0, 5))]
            if rng.random() < 0.5:
                d.ellipse((x, y - gh, x + gw, y + 4), fill=col)
            else:
                d.rectangle((x, y - gh, x + gw, y), fill=col)
            x += gw + int(rng.integers(6, 20))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.30, h * 0.02, w * 0.70, h * 0.30), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    si = Image.composite(Image.new('RGB', (w, h), (150, 110, 64)), si, glow)
    atlas.paste(si, R['shop_in'][:2])
    A._emit_box(emit, R['shop_in'], (20, 14, 8))
    # 雨戶
    w, h = sz('amado')
    am = T._wood_patch(w, h, '#5A4432', 709)
    d = ImageDraw.Draw(am)
    for x in range(0, w, 48):
        d.line((x, 0, x, h), fill=A._hex255('#3A2A1E'), width=3)
    for y in (int(h * 0.12), int(h * 0.5), int(h * 0.88)):
        d.rectangle((0, y - 6, w, y + 6), fill=frame)
    atlas.paste(am, R['amado'][:2])
    # 妻面：灰泥＋露明木構
    w, h = sz('tsuma')
    ts = T._paper(w, h, 710, tone='#DDD4C1')
    d = ImageDraw.Draw(ts)
    for x in (w // 2 - 10, w // 4 - 8, 3 * w // 4 - 8):
        d.rectangle((x, 0, x + 18, h), fill=frame)
    for y in (int(h * 0.38), int(h * 0.74)):
        d.rectangle((0, y, w, y + 16), fill=frame)
    d.rectangle((0, h - 14, w, h), fill=frame)
    a = np.asarray(ts, dtype=np.float32)
    a[:int(h * 0.15)] *= 0.86
    atlas.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), R['tsuma'][:2])
    # 暖簾 ×3（藍／茶／鼠）
    for key, col, n, crest, seed in (('noren_a', '#2E3F5C', 3, 'janome', 711), ('noren_b', '#5A3E2B', 3, 'hishi', 712),
                                     ('noren_c', '#55585A', 2, 'kikko', 713)):
        w, h = sz(key)
        atlas.paste(_noren(w, h, col, n, crest, seed), R[key][:2])
    # 簾
    w, h = sz('sudare')
    sd = Image.new('RGB', (w, h), A._hex255('#9A8456'))
    d = ImageDraw.Draw(sd)
    for y in range(0, h, 6):
        d.line((0, y, w, y), fill=A._hex255('#6E5C3A'), width=2)
    for x in (w // 6, w // 2, 5 * w // 6):
        d.line((x, 0, x, h), fill=A._hex255('#3E3222'), width=4)
    atlas.paste(sd, R['sudare'][:2])
    # 看板（無字）：木板、深框、中央家紋
    w, h = sz('kanban')
    kb = T._wood_patch(w, h, '#6A5238', 714)
    d = ImageDraw.Draw(kb)
    d.rectangle((0, 0, w - 1, h - 1), outline=frame, width=18)
    d.rectangle((26, 26, w - 27, h - 27), outline=A._hex255('#8C7A5A'), width=4)
    _crest(d, w // 2, h // 2, int(h * 0.28), 'janome', A._hex255('#2A2018'))
    atlas.paste(kb, R['kanban'][:2])
    # 店頭商品（籠、俵、壺）
    w, h = sz('goods')
    gd = Image.new('RGB', (w, h), (58, 46, 34))
    d = ImageDraw.Draw(gd)
    rng = np.random.default_rng(715)
    x = 8
    while x < w - 118:
        gw = int(rng.integers(50, 110))
        kind = int(rng.integers(0, 3))
        if kind == 0:     # 籠
            d.rectangle((x, int(h * 0.45), x + gw, h - 6), fill=(150, 124, 78))
            for yy in range(int(h * 0.45), h - 6, 10):
                d.line((x, yy, x + gw, yy), fill=(110, 88, 52), width=2)
            d.ellipse((x + 6, int(h * 0.30), x + gw - 6, int(h * 0.55)), fill=[(170, 60, 40), (190, 150, 60), (90, 120, 60)][int(rng.integers(0, 3))])
        elif kind == 1:   # 俵
            d.ellipse((x, int(h * 0.35), x + gw, h - 6), fill=(176, 156, 108))
            for k in (0.33, 0.66):
                d.line((x + gw * k, int(h * 0.36), x + gw * k, h - 8), fill=(120, 100, 64), width=4)
        else:             # 壺
            d.ellipse((x, int(h * 0.30), x + gw, h - 6), fill=(92, 70, 56))
            d.rectangle((x + gw * 0.3, int(h * 0.22), x + gw * 0.7, int(h * 0.34)), fill=(80, 60, 48))
        x += gw + int(rng.integers(4, 14))
    atlas.paste(gd, R['goods'][:2])
    # ── P6 R2 Variation Pass ──
    # 弁柄格子：紅褐細格子、淺紙背，下 16 % 腰板（同 koshi 構圖，色與密度不同）
    w, h = sz('koshi_r')
    beng, beng_d = A._hex255('#6E2F22'), A._hex255('#4A1F17')
    kr = T._paper(w, h, 721, tone='#D8CBB0')
    d = ImageDraw.Draw(kr)
    kh = int(h * 0.84)
    for x in range(4, w, 17):
        d.rectangle((x, 0, x + 8, kh), fill=beng)
    for x in range(4, w, 68):                                     # 親子格子：每 4 本一條長子（較粗）
        d.rectangle((x - 2, 0, x + 11, kh), fill=beng_d)
    d.rectangle((0, int(h * 0.12), w, int(h * 0.12) + 7), fill=beng_d)
    kr.paste(T._wood_patch(w, h - kh, '#5A2A1E', 731), (0, kh))
    d.rectangle((0, kh - 8, w, kh), fill=beng_d)
    d.rectangle((0, 0, w - 1, h - 1), outline=beng_d, width=14)
    atlas.paste(kr, R['koshi_r'][:2])
    # 蟲籠窓 B：土壁（黃土）＋粗縱格子
    w, h = sz('mushiko_b')
    mb = T._paper(w, h, 722, tone='#B49A76')
    d = ImageDraw.Draw(mb)
    d.rectangle((18, 30, w - 19, h - 31), fill=A._hex255('#2A2119'))
    nb = 10
    pitch = (w - 36 - 24) / nb                                          # 等距：左右留同寬暗縫
    for i in range(nb):
        x = int(18 + (pitch - 24) / 2 + 12 + i * pitch)
        d.rectangle((x, 30, x + 24, h - 31), fill=A._hex255('#A38A66'))
    d.rectangle((18, 30, w - 19, h - 31), outline=A._hex255('#8C7456'), width=10)
    atlas.paste(mb, R['mushiko_b'][:2])
    # 簾 B：舊竹（灰綠褐）、上 22 % 捲起、兩條吊繩
    w, h = sz('sudare_b')
    sb = Image.new('RGB', (w, h), (36, 30, 24))
    d = ImageDraw.Draw(sb)
    top = int(h * 0.22)
    d.rectangle((0, top, w, h), fill=A._hex255('#7A7250'))
    for y in range(top, h, 5):
        d.line((0, y, w, y), fill=A._hex255('#5A5238'), width=2)
    for yy in range(4, top - 4, 8):                                 # 捲起的簾（橫條圓筒感）
        c = int(90 + 40 * np.sin((yy - 4) / max(1, top - 8) * np.pi))
        d.line((0, yy, w, yy), fill=(c, int(c * 0.92), int(c * 0.66)), width=6)
    for x in (w // 5, 4 * w // 5):
        d.line((x, 0, x, h), fill=A._hex255('#2E2418'), width=5)
    d.rectangle((0, h - 8, w, h), fill=A._hex255('#3E3222'))
    atlas.paste(sb, R['sudare_b'][:2])
    # 暖簾 D（生成＝米白、藍亀甲、2 幅）／E（弁柄、白菱、4 幅短暖簾）
    for key, col, n, crest, seed, cc in (('noren_d', '#D8CFBA', 2, 'kikko', 723, (46, 63, 92)),
                                          ('noren_e', '#6E2F22', 4, 'hishi', 724, (226, 220, 204))):
        w, h = sz(key)
        img = T._cloth(w, h, col, seed)
        d = ImageDraw.Draw(img)
        pw = w / n
        for i in range(n):
            x0 = int(i * pw)
            if i:
                d.rectangle((x0 - 3, int(h * 0.10), x0 + 3, h), fill=(20, 18, 16))
            _crest(d, int(x0 + pw / 2), int(h * 0.52), int(min(pw, h) * 0.26), crest, cc)
        d.rectangle((0, 0, w, int(h * 0.10)), fill=tuple(int(c * 0.55) for c in A._hex255(col)))
        atlas.paste(img, R[key][:2])
    # 看板 B（黑漆、金亀甲）／C（白木、墨菱）；無字
    for key, base, frm, crest, cc, seed in (('kanban_b', '#1E1A18', '#5C4A2E', 'kikko', '#B89A5A', 725),
                                             ('kanban_c', '#B8A07A', '#2E2119', 'hishi', '#2A2018', 726)):
        w, h = sz(key)
        kb = T._wood_patch(w, h, base, seed)
        d = ImageDraw.Draw(kb)
        d.rectangle((0, 0, w - 1, h - 1), outline=A._hex255(frm), width=18)
        d.rectangle((26, 26, w - 27, h - 27), outline=A._hex255(cc), width=4)
        _crest(d, w // 2, h // 2, int(h * 0.28), crest, A._hex255(cc))
        atlas.paste(kb, R[key][:2])
    # 2F 窓 B：弁柄粗格子（縱 5 條＋橫 2 條）後面障子
    w, h = sz('window_b')
    wb = T._paper(w, h, 727, tone='#E3DCCB')
    d = ImageDraw.Draw(wb)
    nv = 5                                                              # 弁柄縱格子 5 條，等距；障子桟只走橫向（不和粗格子錯位）
    for i in range(1, nv + 1):
        x = int(w * i / (nv + 1))
        d.rectangle((x - 11, 0, x + 11, h), fill=beng)
    for y in range(40, h, 72):
        d.rectangle((0, y, w, y + 4), fill=A._hex255('#5A4432'))
    for y in (h // 3, 2 * h // 3):
        d.rectangle((0, y - 8, w, y + 8), fill=beng)
    d.rectangle((0, 0, w - 1, h - 1), outline=beng_d, width=24)
    atlas.paste(wb, R['window_b'][:2])
    sws = A._swatches(atlas, R['swatch'], SW, SW_NOTE)
    A._write('machiya_kit', 'V2_MachiyaKit', atlas, emit, R, sws,
             ' P6 R1 模組化町家 Kit（tools/build_village_v2_p6_kit_atlas.py）：千本格子×2、蟲籠窓、小窓、2F 格子窓、障子、'
             '格子引戶、店先內、雨戶、妻面、暖簾×3（幾何家紋）、簾、無字看板、店頭商品；'
             'P6 R2 加：弁柄格子、蟲籠窓 B、舊簾、暖簾 D／E、看板 B／C、2F 窓 B；無文字。')


if __name__ == '__main__':
    build()
