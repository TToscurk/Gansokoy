"""慧音臉部貼圖：下眼瞼臉頰側灰月牙提亮（只動眼睛周圍窄帶；睫毛／眼睛／眉毛不動）。
共用：export_keine_glb.py（Blender numpy）與單獨預覽（PIL）。
arr＝H×W×3 float 0..1，**上到下**（top-down）列序。回傳 (arr_new, info)。
"""
import numpy as np

# 臉 island（top-down 比例，2048 實測：x 0.70–0.82、y 0.21–0.34；臉在 atlas 上下顛倒）
FACE_BOX = (0.70, 0.21, 0.82, 0.34)
# 眼睛搜尋框（2048 實測像素 x 1475–1625、y 530–572；避開 island 間的黑底）
EYE_BOX = (0.720, 0.259, 0.794, 0.280)


def _lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def _components(mask):
    """4-連通標記（純 numpy＋BFS；區域小，夠用）。"""
    H, W = mask.shape
    lab = np.zeros((H, W), np.int32)
    n = 0
    sizes = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if lab[y0, x0]:
            continue
        n += 1
        st = [(y0, x0)]
        lab[y0, x0] = n
        c = 0
        while st:
            y, x = st.pop()
            c += 1
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    st.append((yy, xx))
        sizes.append(c)
    return lab, sizes


def _blur(m, r):
    k = np.ones(2 * r + 1) / (2 * r + 1)
    m = np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 0, m)
    return np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 1, m)


def lift_under_eye(arr, strength=0.8, band=10, dark=0.30):
    H, W, _ = arr.shape
    x0, y0, x1, y1 = (int(FACE_BOX[0] * W), int(FACE_BOX[1] * H), int(FACE_BOX[2] * W), int(FACE_BOX[3] * H))
    R = arr[y0:y1, x0:x1].copy()
    L = _lum(R)
    skin = np.median(R[L > 0.75], axis=0)
    skin_l = float(_lum(skin))
    ex0, ey0 = int(EYE_BOX[0] * W) - x0, int(EYE_BOX[1] * H) - y0
    ex1, ey1 = int(EYE_BOX[2] * W) - x0, int(EYE_BOX[3] * H) - y0
    dm = np.zeros(L.shape, bool)
    dm[ey0:ey1, ex0:ex1] = (L < dark)[ey0:ey1, ex0:ex1]
    lab, sizes = _components(dm)
    # 眼睛＝橫長、不貼搜尋框邊緣的暗塊，取最大兩塊
    cand = []
    for i, sz in enumerate(sizes):
        ys, xs = np.nonzero(lab == i + 1)
        w_, h_ = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
        touch = xs.min() <= ex0 or xs.max() >= ex1 - 1 or ys.min() <= ey0 or ys.max() >= ey1 - 1
        if sz >= 30 and w_ > h_ and not touch:
            cand.append((sz, i + 1))
    eyes = [c[1] for c in sorted(cand, reverse=True)[:2]]
    s = W / 2048.0
    b = max(2, int(round(band * s)))
    mask = np.zeros(L.shape)
    boxes = []
    for e in eyes:
        ys, xs = np.nonzero(lab == e)
        top, bot, lft, rgt = ys.min(), ys.max(), xs.min(), xs.max()
        boxes.append((int(lft + x0), int(top + y0), int(rgt + x0), int(bot + y0)))
        # 臉頰側＝atlas 上方（臉倒放）：每一欄取該欄眼睛最上緣，往上 b 像素
        for x in range(max(lft - 2, 0), min(rgt + 3, L.shape[1])):
            col = np.nonzero(lab[:, x] == e)[0]
            ytop = col.min() if col.size else top
            ya = max(ytop - b, 0)
            mask[ya:ytop + 1, x] = 1.0
    keep = (L >= dark + 0.05) & (L < skin_l - 0.03)        # 不碰睫毛／眼睛、也不碰本來就是膚色
    m = _blur(mask * keep, max(1, int(2 * s))) * keep
    a = np.clip(m, 0, 1) * strength
    R2 = R + (skin[None, None, :] - R) * a[..., None]
    out = arr.copy()
    out[y0:y1, x0:x1] = R2
    info = {'skin_rgb': [round(float(v), 3) for v in skin], 'eyes_px_box': boxes, 'changed_px': int((a > 0.02).sum()),
            'mean_lum_change_in_band': float((_lum(R2) - L)[a > 0.02].mean()) if (a > 0.02).any() else 0.0}
    return out, info
