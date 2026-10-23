"""v2.4 緣一握刀擬合與逐支持刀品質量測（讀 clip_lab dump 的 user://v24_hands/*.json）。

握刀（skill：mixamo two-handed sword pipeline）：
  - 握把軸 = Great Sword Idle（Arm-Space 0）右掌心 → 左掌心方向，在右手骨本地座標系取平均（Mixamo 自己的拳頭）。
  - 拳心 = 右手四指 1~3 節在「垂直握把軸平面」上的最小平方圓心（半徑 ≈ 握把半徑）。
  - 刀背（mune，刀本地 +X）朝虎口（拇指根–食指根中點）；刃朝反向。
  - 刀本地：+Y = 刀尖（握把軸反向，左手在柄尾那側）、y=RIGHT_FIST_Y 為右拳心位置；等比縮放 SWORD_SCALE。
輸出：user://grip_socket.json {"Sword_Hand": Transform3D 字串, ...}，並列出每支 clip：
  左掌心離握把軸距離（cm）、左掌心在柄上的位置（cm，0 = 右拳心、正 = 往柄尾）、刀身中點離軀幹軸距離最小值（cm）。
用法：python tools/v24_anim/grip_fit.py [clip ...]
"""
import json, os, sys
import numpy as np

SWORD_SCALE = 0.68
RIGHT_FIST_Y = 0.02     # 刀本地：柄 -0.38..0.10、鍔 0.10..0.14
HANDS = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "Gansokoy", "v24_hands")
OUT = os.path.join(os.environ["APPDATA"], "Godot", "app_userdata", "Gansokoy", "grip_socket.json")


def load(k):
    return json.load(open(os.path.join(HANDS, k + ".json")))["frames"]


def P(r, b):
    return np.array(r["mixamorig_" + b])


def B(r, b):
    m = np.array(r["mixamorig_" + b + "_basis"]).reshape(3, 3).T  # 欄 = x,y,z
    return m / np.linalg.norm(m, axis=0)


def palm(r, s):
    return (P(r, s + "Hand") + P(r, s + "HandMiddle1")) / 2


def fit_socket(ref="gs_idle_ref"):
    F = load(ref)
    axes, cents, munes = [], [], []
    for r in F:
        Rn = B(r, "RightHand"); O = P(r, "RightHand")
        v = palm(r, "Left") - palm(r, "Right"); ax = Rn.T @ (v / np.linalg.norm(v))
        pts = np.array([Rn.T @ (P(r, "RightHand" + f + str(i)) - O) for f in ["Index", "Middle", "Ring", "Pinky"] for i in [1, 2, 3]])
        e1 = np.cross(ax, [0, 0, 1.0]); e1 /= np.linalg.norm(e1); e2 = np.cross(ax, e1)
        q = np.c_[pts @ e1, pts @ e2]
        sol = np.linalg.lstsq(np.c_[2 * q, np.ones(len(q))], (q ** 2).sum(1), rcond=None)[0]
        c = sol[0] * e1 + sol[1] * e2 + (pts @ ax).mean() * ax
        tm = (Rn.T @ (P(r, "RightHandThumb1") - O) + Rn.T @ (P(r, "RightHandIndex1") - O)) / 2
        mune = tm - c; mune -= ax * (mune @ ax); mune /= np.linalg.norm(mune)
        axes.append(ax); cents.append(c); munes.append(mune)
    ax = np.mean(axes, 0); ax /= np.linalg.norm(ax)
    c = np.mean(cents, 0)
    mune = np.mean(munes, 0); mune -= ax * (mune @ ax); mune /= np.linalg.norm(mune)
    y = -ax                      # 刀尖方向
    x = mune
    z = np.cross(x, y); z /= np.linalg.norm(z)
    x = np.cross(y, z)
    basis = np.c_[x, y, z] * SWORD_SCALE
    origin = c - basis @ np.array([0, RIGHT_FIST_Y, 0])
    return basis, origin, c, ax


def left_shift(basis, origin, ref="gs_idle_ref"):
    """左手拳心離握把軸的偏移（Great Sword Idle 首格量到 5.7 cm）→ 回傳刀本地座標的平移，讓左拳心落在軸上。"""
    r = load(ref)[0]
    Rn = B(r, "RightHand"); O = P(r, "RightHand")
    sb = Rn @ basis; so = O + Rn @ origin
    ay = sb[:, 1] / np.linalg.norm(sb[:, 1]); a0 = so + sb @ np.array([0, RIGHT_FIST_Y, 0])
    pts = np.array([P(r, "LeftHand" + f + str(i)) for f in ["Index", "Middle", "Ring", "Pinky"] for i in [1, 2, 3]])
    e1 = np.cross(ay, [0, 0, 1.0]); e1 /= np.linalg.norm(e1); e2 = np.cross(ay, e1)
    q = np.c_[pts @ e1, pts @ e2]
    sol = np.linalg.lstsq(np.c_[2 * q, np.ones(len(q))], (q ** 2).sum(1), rcond=None)[0]
    c = sol[0] * e1 + sol[1] * e2 + (pts @ ay).mean() * ay
    d = c - a0; perp = d - (d @ ay) * ay
    return np.linalg.solve(sb, -perp), np.linalg.norm(perp)


def fmt(basis, origin):
    b = basis
    vals = [*b[0, :], *b[1, :], *b[2, :], *origin]   # Godot Transform3D 字串是列優先（row-major）
    return "Transform3D(" + ", ".join("%.6f" % v for v in vals) + ")"


def audit(k, basis, origin):
    F = load(k)
    off, along, blade_min, tip_low = [], [], 9.0, 9.0
    head_d, torso_d = [], []
    for r in F:
        Rn = B(r, "RightHand"); O = P(r, "RightHand")
        sb = Rn @ basis; so = O + Rn @ origin
        a0 = so + sb @ np.array([0, RIGHT_FIST_Y, 0])
        ay = sb[:, 1] / np.linalg.norm(sb[:, 1])
        pts = np.array([P(r, "LeftHand" + f + str(i)) for f in ["Index", "Middle", "Ring", "Pinky"] for i in [1, 2, 3]])
        e1 = np.cross(ay, [0, 0, 1.0]); e1 /= np.linalg.norm(e1); e2 = np.cross(ay, e1)
        qq = np.c_[pts @ e1, pts @ e2]
        sol = np.linalg.lstsq(np.c_[2 * qq, np.ones(len(qq))], (qq ** 2).sum(1), rcond=None)[0]
        lc = sol[0] * e1 + sol[1] * e2 + (pts @ ay).mean() * ay     # 左拳心
        lp = lc - a0
        t = lp @ ay
        off.append(np.linalg.norm(lp - t * ay)); along.append(-t)
        # 刀身 5 點到軀幹中軸（髖→頸線段）3D 距離；軀幹半徑約 0.13 m，小於即刀穿身
        h, n = P(r, "Hips"), P(r, "Neck"); u = n - h
        for yy in [0.3, 0.5, 0.7, 0.9, 1.05]:
            p = so + sb @ np.array([0, yy, 0])
            tt = np.clip(np.dot(p - h, u) / np.dot(u, u), 0, 1); qd = p - (h + tt * u)
            blade_min = min(blade_min, np.linalg.norm(qd))   # 3D：刀身點到軀幹中軸線段（髖→頸）
        tip_low = min(tip_low, (so + sb @ np.array([0, 1.05, 0]))[1])
        # 頭（頭骨沿頸→頭方向上移 9 cm 為球心）與刀身最近距離；頭半徑約 11 cm
        hd = P(r, "Head"); hc = hd + (hd - P(r, "Neck")) / max(np.linalg.norm(hd - P(r, "Neck")), 1e-6) * 0.09
        bl = [so + sb @ np.array([0, yy, 0]) for yy in np.linspace(0.16, 1.05, 10)]
        hmin = min(np.linalg.norm(b_ - hc) for b_ in bl)
        head_d.append(hmin)
        tmin = 9.0
        for b_ in bl:
            tt = np.clip(np.dot(b_ - h, u) / np.dot(u, u), 0, 1); tmin = min(tmin, np.linalg.norm(b_ - (h + tt * u)))
        torso_d.append(tmin)
    off = np.array(off) * 100; along = np.array(along) * 100
    on = (off < 2.0) & (along > 5) & (along < 27)   # 左拳心離軸 < 2 cm 且在柄上（柄 5.4~-27.2 cm）
    return dict(frames=len(F), on_hilt_pct=round(100 * on.mean()), off_med=round(float(np.median(off)), 1), off_max=round(float(off.max()), 1),
                along_min=round(float(along.min()), 1), along_max=round(float(along.max()), 1), blade_to_torso_min_cm=round(float(blade_min) * 100, 1),
                tip_lowest_m=round(float(tip_low), 2),
                head_hit_frames=int((np.array(head_d) < 0.11).sum()), head_min_cm=round(float(min(head_d)) * 100, 1),
                torso_hit_frames=int((np.array(torso_d) < 0.13).sum()))


if __name__ == "__main__":
    basis, origin, c, ax = fit_socket()
    print("fist centre (RightHand local m):", c.round(4), " hilt axis R->L:", ax.round(3))
    print("Sword_Hand =", fmt(basis, origin))
    ls, lo = left_shift(basis, origin)
    print("left fist off-axis %.1f cm -> shift (sword local)" % (lo * 100), ls.round(4))
    json.dump({"Sword_Hand": fmt(basis, origin), "fist_centre": c.tolist(), "axis": ax.tolist(), "left_shift": ls.tolist()}, open(OUT, "w"))
    ks = sys.argv[1:] or sorted(f[:-5] for f in os.listdir(HANDS) if f.endswith(".json"))
    for k in ks:
        try:
            print("%-16s" % k, audit(k, basis, origin))
        except Exception as e:
            print(k, "ERR", e)
