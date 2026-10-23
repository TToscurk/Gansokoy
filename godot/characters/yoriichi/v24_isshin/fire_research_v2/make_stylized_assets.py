"""日之呼吸火焰系統：風格化火帶（stroke 層）的原創資產。
1) 碧羅天火環路徑：取 R11 實測刀路（D:/research/sekiro_r8_p0/combat/r11/blade_240_hekira_r11.json；o／b 是相對角色根的本地座標，240 Hz）
   0.53–0.95 s 的刀尖（u=1.085），輕微高斯平滑（σ＝2 樣本＝8 ms）、半徑往平均值收 35%（環更圓，仍貼著刀走過的地方），最後用 0.05 s 的短弧把 345° 補成閉合環。
   輸出 hekira_ring_path.json：[[技能秒, x, y, z], ...]＋中心。
2) 手繪風格火帶貼圖 stylized_flame_band.png（2048×256，線性資料，不得當 sRGB）：
   U＝沿火帶（整圈一張、不重複），V＝0 內緣 → 1 火舌尖端。
   R＝火體距離場（輪廓內越深越大；著色器用門檻切出 黃／橘／紅／深色輪廓 的硬邊色塊）
   G＝黃色核心的位移／寬度變化（含由內側切入的橘色楔形）
   B＝白熱細斜線（沿 U 的細長尖線）
   A＝內部深色摺痕線
   形狀：14 叢火舌（粗肩、尖端銳利、S 形往後甩；每叢 0–2 條副舌）、10 個小鼓包、內緣波浪。
執行：python make_stylized_assets.py
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter1d, distance_transform_edt, gaussian_filter

ROOT = Path(__file__).parent
SRC = Path("D:/research/sekiro_r8_p0/combat/r11/blade_240_hekira_r11.json")
rng = np.random.default_rng(23011)


def ring_path():
    d = json.loads(SRC.read_text())
    T = np.array([r["t"] for r in d])
    P = np.array([np.array(r["o"]) + np.array(r["b"]).reshape(3, 3)[1] * 1.085 for r in d])
    m = (T >= 0.53) & (T <= 0.95)
    T, P = T[m], P[m]
    P = gaussian_filter1d(P, 2, axis=0, mode="nearest")
    c = P.mean(0)
    U, S, Vt = np.linalg.svd(P - c)
    n = Vt[2] if Vt[2][1] > 0 else -Vt[2]
    e1, e2 = Vt[0], np.cross(n, Vt[0])
    x, y = (P - c) @ e1, (P - c) @ e2
    A = np.c_[2 * x, 2 * y, np.ones_like(x)]
    sol = np.linalg.lstsq(A, x * x + y * y, rcond=None)[0]
    cx, cy = sol[:2]
    R = float(np.sqrt(sol[2] + cx * cx + cy * cy))
    C = c + cx * e1 + cy * e2
    # 半徑往平均收 35%（平面內），平面外偏離保留
    rel = P - C
    off = rel @ n
    inp = rel - np.outer(off, n)
    r = np.linalg.norm(inp, axis=1)
    inp = inp / r[:, None] * (0.65 * r + 0.35 * R)[:, None]
    P2 = C + inp + np.outer(off, n)
    # 補閉合：從終點沿圓弧接回起點（技能時間 0.95 → 1.00）
    a0 = np.arctan2(*(np.array([inp[-1] @ e2, inp[-1] @ e1])))
    a1 = np.arctan2(*(np.array([inp[0] @ e2, inp[0] @ e1])))
    da = (a1 - a0) % (2 * np.pi)
    if da > np.pi:
        da -= 2 * np.pi
    sign = np.sign(np.unwrap(np.arctan2(inp @ e2, inp @ e1))[-1] - np.unwrap(np.arctan2(inp @ e2, inp @ e1))[0])
    if np.sign(da) != sign:
        da = da + sign * 2 * np.pi
    k = np.linspace(0, 1, 13)[1:]
    br = []
    for f in k:
        a = a0 + da * f
        rr = (1 - f) * np.linalg.norm(inp[-1]) + f * np.linalg.norm(inp[0])
        oo = (1 - f) * off[-1] + f * off[0]
        br.append(C + rr * (np.cos(a) * e1 + np.sin(a) * e2) + oo * n)
    tb = 0.95 + 0.05 * k
    T3 = np.r_[T, tb]
    P3 = np.r_[P2, np.array(br)]
    step = max(1, len(T3) // 140)
    idx = list(range(0, len(T3), step))
    if idx[-1] != len(T3) - 1:
        idx.append(len(T3) - 1)
    pts = [[round(float(T3[i]), 4)] + [round(float(v), 4) for v in P3[i]] for i in idx]
    seg = np.linalg.norm(np.diff(P3[idx], axis=0), axis=1).sum()
    info = {"source": str(SRC), "window_s": [0.53, 0.95], "closing_arc_s": [0.95, 1.0], "center": [round(float(v), 4) for v in C],
            "normal_up": [round(float(v), 4) for v in n], "radius_m": round(R, 3), "plane_tilt_from_horizontal_deg": round(float(np.degrees(np.arccos(abs(n[1])))), 1),
            "length_m": round(float(seg), 3), "points": pts}
    (ROOT / "hekira_ring_path.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    return info


def bez(p0, p1, p2, n=12):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2


def band_texture():
    W, H = 4096, 512                   # 畫在 2 倍解析度，最後縮成 2048×256
    mask = Image.new("L", (W, H), 0)
    dr = ImageDraw.Draw(mask)
    us = np.linspace(0, 1, 600)
    lowf = lambda s, a: gaussian_filter1d(rng.normal(0, 1, us.size), s, mode="wrap") * a
    y_in = 0.12 + 0.05 * np.abs(np.sin(us * np.pi * 9 + 0.7)) + lowf(14, 0.25) * 0.1
    y_out = 0.55 + lowf(10, 0.25) * 0.25
    y_in = np.clip(y_in, 0.06, 0.22)
    y_out = np.clip(y_out, 0.45, 0.66)
    poly = [(u * W, (1 - yo) * H) for u, yo in zip(us, y_out)] + [(u * W, (1 - yi) * H) for u, yi in zip(us[::-1], y_in[::-1])]
    dr.polygon(poly, fill=255)
    yo_at = lambda u: float(np.interp(u, us, y_out))
    # 主要火舌：14 叢，每叢＝一條粗大彎曲的主舌＋0–2 條貼在背側的副舌（大／中／小），往外＋往後（U 小的一側）甩
    centers = (np.arange(14) + rng.uniform(-0.25, 0.25, 14)) / 14.0

    def tongue(u0, w, base, tip_y, drag, bend):
        L = np.array([u0 - w / 2, base]); Rb = np.array([u0 + w / 2, base]); tip = np.array([u0 + drag, tip_y])
        h = tip_y - base
        # 前緣（U 小側）飽滿外凸、後緣內凹：粗肩、尖端銳利、整體 S 形彎
        lead = np.r_[bez(L, np.array([u0 - w * 0.75 + drag * 0.2, base + h * 0.35]), np.array([u0 - w * 0.25 + drag * 0.7, base + h * 0.72]), 10),
                     bez(np.array([u0 - w * 0.25 + drag * 0.7, base + h * 0.72]), np.array([u0 + drag * (0.9 + bend), base + h * 0.9]), tip, 8)[1:]]
        trail = bez(tip, np.array([u0 + w * 0.05 + drag * 0.55, base + h * 0.55]), Rb, 14)
        return np.r_[lead, trail]

    for u0 in centers:
        w = rng.uniform(0.045, 0.075)
        base = yo_at(u0) - 0.10
        tip_y = rng.uniform(0.86, 0.99)
        drag = -rng.uniform(0.04, 0.085)
        pts = tongue(u0, w, base, tip_y, drag, rng.uniform(-0.2, 0.3))
        dr.polygon([(p[0] * W, (1 - p[1]) * H) for p in pts], fill=255)
        for j in range(rng.integers(0, 3)):            # 副舌：在主舌後方、較短較細
            u1 = u0 + w * rng.uniform(0.5, 1.1) * (j + 1)
            pts = tongue(u1, w * rng.uniform(0.45, 0.7), yo_at(u1) - 0.08, base + (tip_y - base) * rng.uniform(0.45, 0.7), drag * 0.7, 0.0)
            dr.polygon([(p[0] * W, (1 - p[1]) * H) for p in pts], fill=255)
    # 少量寬的小鼓包（不是針刺）
    for u0 in rng.uniform(0.01, 0.99, 10):
        w = rng.uniform(0.02, 0.035)
        base = yo_at(u0) - 0.02
        pts = tongue(u0, w, base, base + rng.uniform(0.07, 0.12), -w * 0.6, 0.0)
        dr.polygon([(p[0] * W, (1 - p[1]) * H) for p in pts], fill=255)
    m = np.asarray(mask).astype(float) / 255.0 > 0.5
    dist = distance_transform_edt(m)
    f = np.clip(dist / (0.20 * H), 0, 1)
    # G：黃色核心位移（低頻）＋內側切入的橘色楔形
    gu = 0.5 + 0.35 * np.tanh(gaussian_filter1d(rng.normal(0, 1, W), 90, mode="wrap") * 3)
    G = np.tile(gu[None, :], (H, 1))
    wedge = Image.new("L", (W, H), 0)
    dw = ImageDraw.Draw(wedge)
    for u0 in rng.uniform(0.02, 0.98, 14):
        w = rng.uniform(0.01, 0.03)
        yi = float(np.interp(u0, us, y_in))
        dw.polygon([((u0 - w) * W, (1 - yi) * H), ((u0 + rng.uniform(-0.03, -0.01)) * W, (1 - (yi + rng.uniform(0.18, 0.3))) * H), ((u0 + w) * W, (1 - yi) * H)], fill=255)
    G = np.clip(G - gaussian_filter(np.asarray(wedge).astype(float) / 255.0, 2) * 0.8, 0, 1)
    # B：白熱細斜線（沿 U、兩端收尖）
    st = Image.new("L", (W, H), 0)
    ds = ImageDraw.Draw(st)
    for _ in range(11):
        u0 = rng.uniform(0.0, 0.93); L = rng.uniform(0.05, 0.12); v0 = rng.uniform(0.22, 0.40); dv = rng.uniform(0.04, 0.12)
        th = rng.uniform(0.02, 0.035)
        ts = np.linspace(0, 1, 20)
        top = [((u0 + L * t) * W, (1 - (v0 + dv * t * t + th * np.sin(np.pi * t) ** 0.7)) * H) for t in ts]
        bot = [((u0 + L * t) * W, (1 - (v0 + dv * t * t - th * 0.3 * np.sin(np.pi * t))) * H) for t in ts[::-1]]
        ds.polygon(top + bot, fill=255)
    B = np.asarray(st).astype(float) / 255.0
    # A：內部深色摺痕（沿主要火舌中線、只畫到 70%）
    cr = Image.new("L", (W, H), 0)
    dc = ImageDraw.Draw(cr)
    for u0 in centers[rng.random(14) < 0.7]:
        base = yo_at(u0) - 0.1
        pts = bez(np.array([u0 + 0.004, base]), np.array([u0 - 0.004, base + 0.15]), np.array([u0 - 0.02, base + 0.27]), 12)
        dc.line([(p[0] * W, (1 - p[1]) * H) for p in pts], fill=255, width=3)
    for _ in range(10):                            # 火體內的折線
        u0 = rng.uniform(0.02, 0.97); v0 = rng.uniform(0.3, 0.5)
        pts = bez(np.array([u0, v0]), np.array([u0 + 0.02, v0 + 0.06]), np.array([u0 + rng.uniform(0.03, 0.06), v0 + rng.uniform(-0.02, 0.08)]), 10)
        dc.line([(p[0] * W, (1 - p[1]) * H) for p in pts], fill=255, width=2)
    A = np.asarray(cr).astype(float) / 255.0 * m
    img = np.uint8(np.clip(np.dstack([f, G, B * m, A]), 0, 1) * 255 + 0.5)
    # 各通道分開縮放（RGBA 一起縮，PIL 會用 alpha 預乘，A＝0 的地方 RGB 全被吃掉）
    chans = [Image.fromarray(img[..., i], "L").resize((2048, 256), Image.LANCZOS) for i in range(4)]
    out = Image.merge("RGBA", chans)
    out.save(ROOT / "stylized_flame_band.png")
    return {"coverage": round(float(m.mean()), 3), "tongue_clusters": 14, "small_bumps": 10, "highlights": 11}


if __name__ == "__main__":
    info = ring_path()
    print({k: v for k, v in info.items() if k != "points"}, "points", len(info["points"]))
    print(band_texture())
