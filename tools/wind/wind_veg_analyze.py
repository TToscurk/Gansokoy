#!/usr/bin/env python3
"""Wind V1.2 植被動態取證分析（wind_capture --seq 的輸出；h0＝正常算繪、h1＝位移熱圖）。

熱圖解碼：植被 shader 在 gw_ctrl.z==1 時輸出 emission = clamp(位移/0.6 m)，場景無光、tonemap linear，
所以像素 sRGB 值 → 線性 → ×0.6 ＝ 該像素的實際頂點位移（m，GPU 真值，不是 CPU 鏡像）。

用法：python tools/wind/wind_veg_analyze.py --dir <capture root> --out <docs dir>
輸出：metrics.json、wind_v12_sheet.jpg（1 張總表）、*.mp4（固定機位影片）
"""
import argparse
import json
import os
import shutil
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HEAT_SCALE = 0.6
VW = "veg_wide"    # 正常算繪（影片、像素動量）
VT = "veg_trees"   # 熱圖、只留樹（高度剖面、樹冠延遲）
VG = "veg_grass"   # 熱圖、只留草（海拔、遮蔽、陣風傳播）
RG = 22            # 草叢 ROI 半徑 px


def font(sz):
    for p in ("C:/Windows/Fonts/msjh.ttc", "C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/arial.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def srgb_to_lin(v):
    v = v / 255.0
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def load_man(d):
    return json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))


def frames_by_key(man):
    out = {}
    for s in man["shots"]:
        out.setdefault(s["key"], []).append(s)
    for k in out:
        out[k].sort(key=lambda s: s["frame"])
    return out


def heat_arr(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    return srgb_to_lin(a.max(axis=2)) * HEAT_SCALE


def roi(arr, px, r):
    x, y = int(round(px[0])), int(round(px[1]))
    h, w = arr.shape
    x0, x1 = max(0, x - r), min(w, x + r + 1)
    y0, y1 = max(0, y - r), min(h, y + r + 1)
    sub = arr[y0:y1, x0:x1]
    nz = sub[sub > 0.002]
    return float(nz.mean()) if nz.size > 8 else 0.0


def tree_profile(arr, base_px, top_px, half_w, bins=20):
    """沿樹軸（base→top 的螢幕投影）每個高度帶取窗口內非零像素的第 90 百分位。"""
    out = []
    h, w = arr.shape
    for i in range(bins):
        t = (i + 0.5) / bins
        cx = base_px[0] + (top_px[0] - base_px[0]) * t
        cy = base_px[1] + (top_px[1] - base_px[1]) * t
        band = abs(top_px[1] - base_px[1]) / bins * 0.5
        y0, y1 = int(max(0, cy - band)), int(min(h, cy + band + 1))
        x0, x1 = int(max(0, cx - half_w)), int(min(w, cx + half_w + 1))
        sub = arr[y0:y1, x0:x1]
        nz = sub[sub > 0.002]
        out.append(float(np.percentile(nz, 90)) if nz.size > 6 else 0.0)
    return out


def arrival(series, dt, frac=0.5):
    s = np.asarray(series)
    base = float(np.median(s[:5]))
    pk = float(s.max())
    if pk - base < 1e-4:
        return None
    thr = base + frac * (pk - base)
    idx = int(np.argmax(s >= thr))
    return idx * dt


def motion(files):
    vals = []
    prev = None
    for f in files:
        a = np.asarray(Image.open(f).convert("L"), dtype=np.float64)
        if prev is not None:
            vals.append(float(np.abs(a - prev).mean()))
        prev = a
    return float(np.mean(vals)) if vals else 0.0


def ffmpeg_video(files, out_mp4, fps=10, colormap=False, tmp=None):
    exe = shutil.which("ffmpeg")
    if exe is None:
        return False
    src = files
    if colormap:
        os.makedirs(tmp, exist_ok=True)
        src = []
        for i, f in enumerate(files):
            p = os.path.join(tmp, f"c{i:04d}.png")
            Image.fromarray(colorize(heat_arr(f))).save(p)
            src.append(p)
    lst = out_mp4 + ".txt"
    with open(lst, "w", encoding="utf-8") as fh:
        for f in src:
            fh.write(f"file '{os.path.abspath(f)}'\nduration {1.0 / fps}\n")
    cmd = [exe, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst,
           "-vf", "scale=960:-2,format=yuv420p", "-r", str(fps), "-c:v", "libx264", "-crf", "20", out_mp4]
    r = subprocess.run(cmd)
    os.remove(lst)
    return r.returncode == 0


def colorize(d):
    """位移（m）→ 偽色：0 黑 → 藍 → 綠 → 黃 → 紅（0.6 m）。"""
    t = np.clip(d / HEAT_SCALE, 0, 1)
    stops = np.array([[0, 0, 0], [30, 60, 200], [40, 200, 90], [240, 220, 40], [230, 40, 30]], dtype=np.float64)
    x = t * (len(stops) - 1)
    i = np.clip(x.astype(int), 0, len(stops) - 2)
    f = (x - i)[..., None]
    rgb = stops[i] * (1 - f) + stops[i + 1] * f
    return rgb.astype(np.uint8)


def plot(draw, box, series, colors, labels, title, xlab, ylab, xs=None, ft=None, fl=None):
    x0, y0, x1, y1 = box
    draw.rectangle(box, fill=(250, 250, 248), outline=(120, 120, 120))
    draw.text((x0 + 8, y0 + 4), f"{title}（縱軸 {ylab}）", fill=(20, 20, 20), font=ft)
    px0, py0, px1, py1 = x0 + 52, y0 + 40, x1 - 12, y1 - 40
    ymax = max(max(s) for s in series) * 1.08 or 1.0
    n = max(len(s) for s in series)
    for k in range(5):
        yy = py1 - (py1 - py0) * k / 4
        draw.line((px0, yy, px1, yy), fill=(225, 225, 225))
        draw.text((x0 + 4, yy - 8), f"{ymax * k / 4:.2f}", fill=(80, 80, 80), font=fl)
    for s, c, lab in zip(series, colors, labels):
        pts = []
        for i, v in enumerate(s):
            xv = xs[i] if xs else i
            xn = (xv - (xs[0] if xs else 0)) / max(((xs[-1] - xs[0]) if xs else n - 1), 1e-6)
            pts.append((px0 + (px1 - px0) * xn, py1 - (py1 - py0) * (v / ymax)))
        if len(pts) > 1:
            draw.line(pts, fill=c, width=3)
    lx = px0 + 6
    for c, lab in zip(colors, labels):
        draw.rectangle((lx, py0 + 4, lx + 14, py0 + 14), fill=c)
        draw.text((lx + 18, py0), lab, fill=(30, 30, 30), font=fl)
        lx += 18 + int(draw.textlength(lab, font=fl)) + 16
    x_lo = xs[0] if xs else 0.0
    x_hi = xs[-1] if xs else 1.0
    for k in range(5):
        xx = px0 + (px1 - px0) * k / 4
        draw.line((xx, py1, xx, py1 + 4), fill=(80, 80, 80))
        lab_t = f"{x_lo + (x_hi - x_lo) * k / 4:.1f}" if xs else f"{k / 4:.2f}"
        draw.text((xx - 10, py1 + 5), lab_t, fill=(80, 80, 80), font=fl)
    draw.text((px0 + (px1 - px0) * 0.30, py1 + 18), xlab, fill=(60, 60, 60), font=fl)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    m0 = load_man(os.path.join(args.dir, "h0"))
    m1 = load_man(os.path.join(args.dir, "h1"))
    f0 = frames_by_key(m0)
    f1 = frames_by_key(m1)
    dt = float(m1["step"])
    PT = {k: v["px"] for k, v in m1["views"][VT]["probes"].items()}
    PG = {k: v["px"] for k, v in m1["views"][VG]["probes"].items()}
    W = {k: v["world"] for k, v in m1["views"][VT]["probes"].items()}
    P = PT
    met = {"heat_scale_m": HEAT_SCALE, "step_s": dt}

    # ── 1. 高度剖面（gust 狀態平均）：tree2＝keyaki 高木 18.8 m、tree1＝momiji 小樹 6.8 m
    gust_heat = [heat_arr(s["file"]) for s in f1[f"{VT}_gust"]]
    trees = {"tall_keyaki": 2, "short_momiji": 1}
    prof = {}
    for name, i in trees.items():
        b, t = P[f"tree{i}_base"], P[f"tree{i}_top"]
        hpx = abs(t[1] - b[1])
        half_w = max(6.0, hpx * 0.06)
        acc = np.zeros(20)
        for a in gust_heat:
            acc += np.asarray(tree_profile(a, b, t, half_w))
        acc /= len(gust_heat)
        prof[name] = [round(float(v), 4) for v in acc]
        met[f"profile_{name}"] = {
            "height_m": W[f"tree{i}_h"][0],
            "bins_0_to_1": prof[name],
            "root_0_10pct_m": round(float(np.mean(acc[:2])), 4),
            "mid_45_55pct_m": round(float(np.mean(acc[9:11])), 4),
            "tip_90_100pct_m": round(float(np.mean(acc[18:20])), 4),
            "max_m": round(float(acc.max()), 4),
        }

    # ── 2. 三個狀態（calm／breeze／gust）：全畫面植被平均位移 ＋ 正常算繪像素動量
    states = {}
    for st in ("calm", "breeze", "gust"):
        hs = [heat_arr(s["file"]) for s in f1[f"{VT}_{st}"]]
        hg = [heat_arr(s["file"]) for s in f1[f"{VG}_{st}"]]
        allv = np.concatenate([a[a > 0.002] for a in hs + hg]) if hs else np.array([0.0])
        states[st] = {
            "veg_mean_disp_m": round(float(allv.mean()) if allv.size else 0.0, 4),
            "veg_p95_disp_m": round(float(np.percentile(allv, 95)) if allv.size else 0.0, 4),
            "tall_tip_m": round(float(np.mean([np.mean(tree_profile(a, P["tree2_base"], P["tree2_top"], 8)[18:20]) for a in hs])), 4),
            "grass_ground_m": round(float(np.mean([roi(a, PG["grass_ground"], RG) for a in hg])), 4),
            "pixel_motion_0_255": round(motion([s["file"] for s in f0[f"{VW}_{st}"]]), 3),
        }
    met["states"] = states

    # ── 3. 海拔與遮蔽（breeze＋gust 平均）
    both = [heat_arr(s["file"]) for s in f1[f"{VG}_breeze"] + f1[f"{VG}_gust"]]
    met["elevation"] = {
        "grass_mound_top_5m_m": round(float(np.mean([roi(a, PG["grass_mound"], RG) for a in both])), 4),
        "grass_ground_m": round(float(np.mean([roi(a, PG["grass_ground"], RG) for a in both])), 4),
    }
    met["shelter"] = {
        "grass_behind_wall_m": round(float(np.mean([roi(a, PG["grass_shelter"], RG) for a in both])), 4),
        "grass_open_m": round(float(np.mean([roi(a, PG["grass_open"], RG) for a in both])), 4),
    }

    # ── 4. 行進陣風（gustline：風向 +X、一道 0.9 陣風從 x=−20 生成）：各草叢抵達時間
    gl = [heat_arr(s["file"]) for s in f1[f"{VG}_gustline"]]
    glt = [heat_arr(s["file"]) for s in f1[f"{VT}_gustline"]]
    prop = {}
    series_g = []
    for k in range(5):
        ser = [roi(a, PG[f"grass_x{k}"], RG) for a in gl]
        series_g.append(ser)
        prop[f"x={W[f'grass_x{k}'][0]:+.1f}m"] = arrival(ser, dt)
    met["propagation_arrival_s"] = prop

    # ── 5. 樹冠延遲（gustline，高木）：主幹中段（hn 0.25–0.40）vs 樹冠上段（0.80–0.95）
    trunk_s, crown_s = [], []
    # 小樹在 x=−6、高木在 x=+7.5：陣風依序抵達
    for a in glt:
        pr = tree_profile(a, P["tree2_base"], P["tree2_top"], 10)
        trunk_s.append(float(np.mean(pr[5:8])))
        crown_s.append(float(np.mean(pr[16:19])))
    it, ic = int(np.argmax(trunk_s)), int(np.argmax(crown_s))

    def fall_time(s, i0):
        s = np.asarray(s)
        base = float(np.median(s[:5]))
        half = base + 0.5 * (s[i0] - base)
        for j in range(i0, len(s)):
            if s[j] <= half:
                return j * dt
        return None

    met["crown_lag_tall"] = {
        "trunk_peak_s": round(it * dt, 2), "crown_peak_s": round(ic * dt, 2),
        "trunk_half_decay_s": fall_time(trunk_s, it), "crown_half_decay_s": fall_time(crown_s, ic),
        "trunk_peak_m": round(trunk_s[it], 4), "crown_peak_m": round(crown_s[ic], 4),
    }

    small_crown = [float(np.mean(tree_profile(a, P["tree1_base"], P["tree1_top"], 10)[14:19])) for a in glt]
    met["propagation_trees_peak_s"] = {
        "short_momiji_x-6": round(int(np.argmax(small_crown)) * dt, 2),
        "tall_keyaki_x+7.5": round(ic * dt, 2),
    }

    # ── 6. 同一像素 A/B（選填：<dir>/ab，seq＝ab_on／ab_off，只差海拔增益與遮蔽）
    ab_dir = os.path.join(args.dir, "ab")
    if os.path.exists(os.path.join(ab_dir, "manifest.json")):
        mab = load_man(ab_dir)
        fab = frames_by_key(mab)
        PA = {k: v["px"] for k, v in mab["views"][VG]["probes"].items()}
        on = [heat_arr(s["file"]) for s in fab[f"{VG}_ab_on"]]
        off = [heat_arr(s["file"]) for s in fab[f"{VG}_ab_off"]]
        ab = {}
        for k in ("grass_mound", "grass_ground", "grass_shelter", "grass_open"):
            a_on = float(np.mean([roi(x, PA[k], RG) for x in on]))
            a_off = float(np.mean([roi(x, PA[k], RG) for x in off]))
            ab[k] = {"on_m": round(a_on, 4), "off_m": round(a_off, 4), "ratio": round(a_on / max(a_off, 1e-6), 3)}
        met["ab_same_pixels"] = ab
    json.dump(met, open(os.path.join(args.out, "metrics.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    # ── 影片（固定機位）：正常算繪四段串接＋熱圖偽色同序列
    seq_keys = [f"{VW}_{k}" for k in ("calm", "breeze", "gust", "gustline")]
    ok1 = ffmpeg_video([s["file"] for k in seq_keys for s in f0[k]], os.path.join(args.out, "pilot_veg_states.mp4"))
    ok2 = ffmpeg_video([s["file"] for s in f1[f"{VT}_gustline"]], os.path.join(args.out, "pilot_veg_gustline_heat_trees.mp4"),
                       colormap=True, tmp=os.path.join(args.dir, "_cmap_t"))
    ok4 = ffmpeg_video([s["file"] for s in f1[f"{VG}_gustline"]], os.path.join(args.out, "pilot_veg_gustline_heat_grass.mp4"),
                       colormap=True, tmp=os.path.join(args.dir, "_cmap_g"))
    ok3 = ffmpeg_video([s["file"] for s in f0[f"{VW}_gustline"]], os.path.join(args.out, "pilot_veg_gustline.mp4"))
    met["videos"] = {"states": ok1, "gustline_heat_trees": ok2, "gustline_heat_grass": ok4, "gustline": ok3}

    # ── 總表（1 張）
    ft, fl = font(20), font(15)
    TW, TH = 640, 360
    sheet = Image.new("RGB", (TW * 3 + 40, TH * 2 + 360 + 50), (236, 236, 232))
    dr = ImageDraw.Draw(sheet)
    g_f0 = f0[f"{VW}_gust"]
    tiles = [
        (Image.open(g_f0[len(g_f0) // 2]["file"]), "正常算繪：Strong Gust（固定機位）"),
        (Image.fromarray(colorize(heat_arr(f1[f"{VT}_breeze"][10]["file"]))), "位移熱圖（樹）：Breeze（黑0 → 紅0.6 m）"),
        (Image.fromarray(colorize(gust_heat[len(gust_heat) // 2])), "位移熱圖（樹）：Strong Gust"),
    ]
    for j, k in enumerate((0.25, 0.45, 0.65)):
        idx = min(len(gl) - 1, int(len(gl) * k))
        tiles.append((Image.fromarray(colorize(gl[idx])), f"草叢熱圖：行進陣風 t={idx * dt:.1f} s（風向 +X，左→右）"))
    for n, (im, cap) in enumerate(tiles):
        x = 10 + (n % 3) * (TW + 10)
        y = 10 + (n // 3) * (TH + 10)
        sheet.paste(im.resize((TW, TH)), (x, y))
        dr.rectangle((x, y, x + int(dr.textlength(cap, font=fl)) + 12, y + 24), fill=(0, 0, 0))
        dr.text((x + 6, y + 3), cap, fill=(255, 255, 255), font=fl)
    y2 = 20 + 2 * (TH + 10)
    plot(dr, (10, y2, 10 + TW, y2 + 340),
         [prof["tall_keyaki"], prof["short_momiji"]], [(200, 60, 40), (40, 110, 200)],
         [f"高木 keyaki {W['tree2_h'][0]:.1f} m", f"小樹 momiji {W['tree1_h'][0]:.1f} m"],
         "高度剖面（Strong Gust 平均位移，GPU 實測）", "樹基 0 → 樹梢 1（正規化高度）", "m", ft=ft, fl=fl)
    cols = [(40, 40, 160), (40, 140, 200), (40, 170, 90), (220, 160, 30), (200, 50, 40)]
    xs_t = [i * dt for i in range(len(gl))]
    plot(dr, (20 + TW, y2, 20 + 2 * TW, y2 + 340), series_g, cols,
         [f"x{W[f'grass_x{k}'][0]:+.0f}" for k in range(5)],
         "行進陣風：各草叢位移 vs 時間", "時間 s（一道 0.9 陣風自 x=−20 m 出發）", "m", xs=xs_t, ft=ft, fl=fl)
    plot(dr, (30 + 2 * TW, y2, 30 + 3 * TW, y2 + 340), [trunk_s, crown_s], [(120, 90, 50), (40, 160, 70)],
         ["主幹中段 0.25–0.40", "樹冠上段 0.80–0.95"],
         "高木：主幹 vs 樹冠（延遲回正）", "時間 s", "m", xs=xs_t, ft=ft, fl=fl)
    st = met["states"]
    line = "狀態  calm／breeze／gust：植被平均位移 %.3f／%.3f／%.3f m；高木樹梢 %.3f／%.3f／%.3f m；像素動量 %.2f／%.2f／%.2f" % (
        st["calm"]["veg_mean_disp_m"], st["breeze"]["veg_mean_disp_m"], st["gust"]["veg_mean_disp_m"],
        st["calm"]["tall_tip_m"], st["breeze"]["tall_tip_m"], st["gust"]["tall_tip_m"],
        st["calm"]["pixel_motion_0_255"], st["breeze"]["pixel_motion_0_255"], st["gust"]["pixel_motion_0_255"])
    dr.text((14, y2 + 350), line, fill=(20, 20, 20), font=fl)
    sheet.save(os.path.join(args.out, "wind_v12_sheet.jpg"), quality=88)
    json.dump(met, open(os.path.join(args.out, "metrics.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(json.dumps(met, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
