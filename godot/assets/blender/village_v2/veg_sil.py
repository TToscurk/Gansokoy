"""P9 植被庫：LOD 剪影一致性量測（build_veg_kit.py --sil 呼叫；也可單獨 import）。

把每級網格（樹皮不透明＋葉卡用 atlas alpha）正交投影到 4 個水平方位（0／45／90／135°），細格 0.08 m 光柵化、
3×3 平均降到 0.24 m 格，覆蓋 ≥ 0.35 算「有樹」（近似遠距 mip 平均＋shader alpha_mip_boost）。逐級比較：
  iou     兩級剪影交集／聯集（4 方位平均）
  width   樹冠寬（每方位剪影第 2～98 百分位欄位寬）差／LOD0 冠寬
  center  剪影質心水平位移（m）
  top     樹頂（最高有樹格）高度差（m）
  gap     樹冠內「天空洞」重疊：逐列把最左～最右之間的空格當洞，兩級洞集合 IoU（洞太少則略過）
不是 gate 本身：數字寫進 src/lod_silhouette.json 給 ART_REVIEW 參考，視覺判定仍看換檔掃描圖。
"""
import math

import numpy as np

FINE = 0.08
DOWN = 3
COV = 0.35
AZ = (0.0, 45.0, 90.0, 135.0)
ALPHA_CUT = 0.5


class AtlasAlpha:
    """atlas alpha（降一級 mip：1024²，box 平均）。"""

    def __init__(self, bpy, paths):
        self.a = {}
        for key, p in paths.items():
            img = bpy.data.images.load(p, check_existing=True)
            w, h = img.size
            px = np.empty(w * h * 4, dtype=np.float32)
            img.pixels.foreach_get(px)
            al = px.reshape(h, w, 4)[::-1, :, 3]          # Blender 由下往上 → 轉成 v 向下（與 UV 一致）
            al = al.reshape(h // 2, 2, w // 2, 2).mean((1, 3))
            self.a[key] = al

    def sample(self, key, u, v):
        al = self.a[key]
        h, w = al.shape
        x = np.clip((u * w).astype(np.int64), 0, w - 1)
        y = np.clip((v * h).astype(np.int64), 0, h - 1)
        return al[y, x]


def _tris(mb):
    P = np.asarray(mb.P, dtype=np.float64)
    UV = np.asarray(mb.UV, dtype=np.float64)
    tri, mat = [], []
    for f, m in zip(mb.F, mb.FM):
        for k in range(1, len(f) - 1):
            tri.append((f[0], f[k], f[k + 1]))
            mat.append(m)
    return P, UV, np.asarray(tri, dtype=np.int64), np.asarray(mat, dtype=np.int64)


def raster(mb, atlas, az_deg, origin, shape):
    """回傳 0.24 m 格覆蓋率遮罩（bool）。origin＝(水平最小, 高度最小)，shape＝細格 (rows, cols)。"""
    P, UV, T, M = _tris(mb)
    a = math.radians(az_deg)
    ax = np.array([math.cos(a), 0.0, math.sin(a)])
    X = P @ ax
    Y = P[:, 1]
    xs = (X - origin[0]) / FINE
    ys = (Y - origin[1]) / FINE
    rows, cols = shape
    acc = np.zeros(rows * cols, dtype=np.float32)
    leaf_key = {}
    for i, m in enumerate(mb.mats):
        leaf_key[i] = m.split('_')[-1] if m.startswith('VK_Leaf_') else None
    x0, y0 = xs[T[:, 0]], ys[T[:, 0]]
    x1, y1 = xs[T[:, 1]], ys[T[:, 1]]
    x2, y2 = xs[T[:, 2]], ys[T[:, 2]]
    det = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    ok = np.abs(det) > 1e-9
    bx0 = np.floor(np.minimum(np.minimum(x0, x1), x2)).astype(np.int64)
    bx1 = np.ceil(np.maximum(np.maximum(x0, x1), x2)).astype(np.int64)
    by0 = np.floor(np.minimum(np.minimum(y0, y1), y2)).astype(np.int64)
    by1 = np.ceil(np.maximum(np.maximum(y0, y1), y2)).astype(np.int64)
    bx0, by0 = np.clip(bx0, 0, cols - 1), np.clip(by0, 0, rows - 1)
    bx1, by1 = np.clip(bx1, 0, cols - 1), np.clip(by1, 0, rows - 1)
    nw, nh = bx1 - bx0 + 1, by1 - by0 + 1
    cnt = np.where(ok, nw * nh, 0)
    # 一次展開所有三角形的 bbox 像素（分批避免記憶體爆）
    idx = np.nonzero(cnt)[0]
    CH = 4000
    for s in range(0, len(idx), CH):
        ii = idx[s:s + CH]
        c = cnt[ii]
        tid = np.repeat(ii, c)
        off = np.arange(c.sum()) - np.repeat(np.cumsum(c) - c, c)
        px = bx0[tid] + off % nw[tid]
        py = by0[tid] + off // nw[tid]
        cx, cy = px + 0.5, py + 0.5
        d = det[tid]
        l0 = ((y1[tid] - y2[tid]) * (cx - x2[tid]) + (x2[tid] - x1[tid]) * (cy - y2[tid])) / d
        l1 = ((y2[tid] - y0[tid]) * (cx - x2[tid]) + (x0[tid] - x2[tid]) * (cy - y2[tid])) / d
        l2 = 1.0 - l0 - l1
        inside = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        tid, px, py, l0, l1, l2 = tid[inside], px[inside], py[inside], l0[inside], l1[inside], l2[inside]
        keep = np.ones(len(tid), dtype=bool)
        mats = M[tid]
        for mi, key in leaf_key.items():
            if key is None:
                continue
            sel = mats == mi
            if not sel.any():
                continue
            tt = T[tid[sel]]
            u = UV[tt[:, 0], 0] * l0[sel] + UV[tt[:, 1], 0] * l1[sel] + UV[tt[:, 2], 0] * l2[sel]
            v = UV[tt[:, 0], 1] * l0[sel] + UV[tt[:, 1], 1] * l1[sel] + UV[tt[:, 2], 1] * l2[sel]
            keep[np.nonzero(sel)[0]] = atlas.sample(key, u, v) >= ALPHA_CUT
        acc[(py[keep] * cols + px[keep])] = 1.0
    m = acc.reshape(rows, cols)
    r2, c2 = rows // DOWN, cols // DOWN
    m = m[:r2 * DOWN, :c2 * DOWN].reshape(r2, DOWN, c2, DOWN).mean((1, 3))
    return m >= COV


def _extent(mask):
    cols = np.nonzero(mask.any(0))[0]
    if not len(cols):
        return 0.0, 0.0
    colw = mask.sum(0).astype(np.float64)
    cs = np.cumsum(colw) / max(colw.sum(), 1)
    lo = int(np.searchsorted(cs, 0.02))
    hi = int(np.searchsorted(cs, 0.98))
    xs = np.arange(mask.shape[1])
    cx = float((colw * xs).sum() / max(colw.sum(), 1))
    return (hi - lo + 1), cx


def _gaps(mask, ymin_row):
    g = np.zeros_like(mask)
    for r in range(ymin_row, mask.shape[0]):
        c = np.nonzero(mask[r])[0]
        if len(c) >= 2:
            g[r, c[0]:c[-1] + 1] = ~mask[r, c[0]:c[-1] + 1]
    return g


def compare(lods, atlas, crown_y0):
    """lods：MB 清單。回傳逐級比較 [{'pair': 'k→k+1', iou, width, center, top, gap}]＋ LOD0 冠寬。"""
    allp = np.concatenate([np.asarray(mb.P) for mb in lods])
    rmax = float(np.sqrt((allp[:, 0] ** 2 + allp[:, 2] ** 2).max())) + 0.5
    ymin, ymax = float(allp[:, 1].min()) - 0.2, float(allp[:, 1].max()) + 0.5
    cols = int(math.ceil(2 * rmax / FINE / DOWN)) * DOWN
    rows = int(math.ceil((ymax - ymin) / FINE / DOWN)) * DOWN
    cell = FINE * DOWN
    masks = []
    for mb in lods:
        masks.append([raster(mb, atlas, az, (-rmax, ymin), (rows, cols)) for az in AZ])
    crow = max(0, int((crown_y0 - ymin) / cell))
    w0 = np.mean([_extent(m)[0] for m in masks[0]]) * cell
    out = []
    for k in range(len(lods) - 1):
        A, B = masks[k], masks[k + 1]
        iou, dw, dc, dt, giou = [], [], [], [], []
        for a, b in zip(A, B):
            inter = float((a & b).sum())
            uni = float((a | b).sum())
            iou.append(inter / max(uni, 1))
            wa, ca = _extent(a)
            wb, cb = _extent(b)
            dw.append((wb - wa) * cell / max(w0, 1e-3))
            dc.append(abs(cb - ca) * cell)
            ta = np.nonzero(a.any(1))[0]
            tb = np.nonzero(b.any(1))[0]
            dt.append(((tb[-1] if len(tb) else 0) - (ta[-1] if len(ta) else 0)) * cell)
            ga, gb = _gaps(a, crow), _gaps(b, crow)
            if ga.sum() >= 12 and gb.sum() >= 12:
                giou.append(float((ga & gb).sum()) / max(float((ga | gb).sum()), 1))
        out.append({'pair': '%d→%d' % (k, k + 1), 'iou': round(float(np.mean(iou)), 3), 'iou_min': round(float(np.min(iou)), 3),
                    'width': round(float(np.mean(dw)), 3), 'width_max': round(float(max(dw, key=abs)), 3),
                    'center_m': round(float(np.max(dc)), 2), 'top_m': round(float(max(dt, key=abs)), 2),
                    'gap_iou': round(float(np.mean(giou)), 3) if giou else None})
    return {'crown_w_proj': round(float(w0), 2), 'pairs': out}
