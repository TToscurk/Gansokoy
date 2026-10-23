"""手指扭曲量測（依權重歸屬取樣，排除鄰指污染）。

前版用骨軸圓柱取樣，指根處半徑內必然圈到鄰指與手掌，量到的 80 度「扭轉」
其實是鄰指截面混入造成的假訊號（控制骨顯示為 Thumb1/Thumb2/Hand）。
本版只取「主控骨屬於該指」的頂點。
"""
import bpy
import numpy as np

bpy.ops.wm.open_mainfile(filepath=r"D:/神社/shrine/work/緣一_rigged.blend")
body = bpy.data.objects["身體2"]
me = body.data
M = body.matrix_world
arm = bpy.data.objects["Armature"]
co = np.array([[(M @ v.co).x, (M @ v.co).y, (M @ v.co).z] for v in me.vertices])

# 每個頂點的主控骨
dom = {}
for v in me.vertices:
    best, bw = None, 0.0
    for g in v.groups:
        if g.weight > bw:
            bw, best = g.weight, body.vertex_groups[g.group].name
    dom[v.index] = best

print("TW side finger  len  n  | 逐段扭轉(度)  | 扁平度 | 半徑mm")
worst = []
for side in ("Left", "Right"):
    for f in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
        own = {f"{side}Hand{f}{i}" for i in (1, 2, 3)}
        idx = np.array([i for i, b in dom.items() if b in own])
        if len(idx) < 30:
            print(f"TW {side}{f} few {len(idx)}")
            continue
        b1 = arm.data.bones[f"{side}Hand{f}1"]
        b3 = arm.data.bones[f"{side}Hand{f}3"]
        a = np.array(b1.head_local)
        t = np.array(b3.tail_local)
        ax = t - a
        L = np.linalg.norm(ax)
        ax = ax / L
        R = co[idx] - a
        d = R @ ax
        perp = R - np.outer(d, ax)

        # 用「同一條縱向稜線的角位置」量扭轉。
        # 不可用 SVD 主軸：截面接近正圓時（flat 0.9+）主軸方向本無意義，
        # 會在數值噪聲中亂指，量出 70-82 度的假扭轉。
        ref = np.array([0.0, 0.0, 1.0])
        if abs(float(ax @ ref)) > 0.95:
            ref = np.array([0.0, 1.0, 0.0])
        u = ref - ax * float(ax @ ref)
        u = u / np.linalg.norm(u)
        v = np.cross(ax, u)
        ang = np.degrees(np.arctan2(perp @ v, perp @ u))

        rows = []
        for k in range(8):
            lo, hi = L * k / 8, L * (k + 1) / 8
            m = (d >= lo) & (d < hi)
            if m.sum() < 5:
                continue
            P = perp[m]
            # 取該片中最靠近 +u 方向的頂點當稜線代表點
            j = int(np.argmin(np.abs(((ang[m] + 180) % 360) - 180)))
            rows.append((float(ang[m][j]),
                         float(np.linalg.norm(P, axis=1).min()
                               / max(np.linalg.norm(P, axis=1).max(), 1e-9)),
                         float(np.linalg.norm(P, axis=1).mean())))
        angs = []
        for i in range(1, len(rows)):
            dd = abs(rows[i][0] - rows[i - 1][0]) % 360
            angs.append(round(min(dd, 360 - dd), 1))
        flats = [round(r[1], 2) for r in rows]
        rads = [round(r[2] * 1000, 1) for r in rows]
        mx = max(angs) if angs else 0.0
        worst.append((mx, f"{side}{f}"))
        print(f"TW {side}{f} L={L*100:.1f} n={len(idx)} max={mx:.1f} {angs}")
        print(f"TW    flat={flats} rad={rads}")

worst.sort(reverse=True)
print("TW WORST", worst[:5])
