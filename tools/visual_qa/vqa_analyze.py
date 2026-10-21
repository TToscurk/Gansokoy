"""P2 Visual QA 影像分析（numpy／PIL；只讀 vqa_capture.gd 的輸出，不碰場景）。

所有量測都從「純色 ID 遮罩」＋相機資料算：正交視角 1 px = m_per_px 公尺，像素位移用相機基底換回世界向量，
再投影到建築座標（right / up / front）。透視視角只拿來看，不算公尺。
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

STATUSES = ("PASS", "WARN", "FAIL", "UNKNOWN", "REVIEW")
ID_TOL = 12          # ID 色容差（8-bit）
DIFF_TOL = 10        # 一般／隱藏影像差異門檻（8-bit，任一通道）
MIN_FRAC = 0.002     # 目標至少佔畫面 0.2 % 才算「在畫面內」
OCCLUDED = 0.5       # 可見率低於此 → UNKNOWN（被遮住，不能當沒問題）
PARTIAL = 0.9        # 可見率低於此 → WARN（部分遮擋）


def vrow(rule_id, typ, status, objs=None, expected=None, actual=None, deviation=None, tol=None, method="",
         suggestion="", evidence=None, error_class=None, section="visual", images=None, camera=None):
    """與 arch_spatial._row 同欄位，另加 section／error_class／images／camera。"""
    return {"rule_id": rule_id, "type": typ, "status": status, "object_ids": objs or [], "expected": expected,
            "actual": actual, "deviation": deviation, "tolerance": tol, "method": method, "suggestion": suggestion,
            "evidence": evidence or {}, "error_class": error_class, "section": section, "images": images or [],
            "camera": camera}


def load(d):
    with open(os.path.join(d, "manifest.json"), encoding="utf-8") as f:
        return json.load(f)


def img(d, name):
    return np.asarray(Image.open(os.path.join(d, name)).convert("RGB")).astype(np.int16)


def id_masks(a, parts, ground_color=None):
    out = {}
    for p in parts:
        out[p["name"]] = np.abs(a - np.array(p["color"])).max(axis=2) <= ID_TOL
    if ground_color is not None:
        out["__ground"] = np.abs(a - np.array(ground_color)).max(axis=2) <= ID_TOL
    return out


def union(masks, skip=("__ground",)):
    u = None
    for k, m in masks.items():
        if k in skip:
            continue
        u = m.copy() if u is None else (u | m)
    return u


def bbox(m):
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def cam_axes(e):
    c = e["camera"]
    return np.array(c["x"]), np.array(c["y"]), np.array(c["z"])


def px_to_world_delta(e, dx, dy):
    """正交影像像素位移 → 世界向量（影像 y 向下）。"""
    x, y, _ = cam_axes(e)
    s = e["m_per_px"]
    return x * dx * s - y * dy * s


def to_rfu(frame, v):
    return np.array([np.dot(v, frame["right"]), np.dot(v, frame["up"]), np.dot(v, frame["front"])])


# ─────────────────────────── B4 截圖可靠性 ───────────────────────────

def reliability(d, man, e):
    res = tuple(man["resolution"])
    rows, notes = [], {}
    a = img(d, e["file"])
    h, w = a.shape[:2]
    rid = f"VIS_RELIABLE:{e['view']}"
    imgs = [e["file"]]
    if (w, h) != res:
        return vrow(rid, "CAPTURE", "UNKNOWN", actual={"resolution": [w, h]}, expected={"resolution": list(res)},
                    method="image size", suggestion="解析度不符，影像不可比較", images=imgs), None
    lum = a.mean()
    if lum < 4 or a.std() < 1.5:
        return vrow(rid, "CAPTURE", "UNKNOWN", actual={"mean": float(lum), "std": float(a.std())},
                    method="mean/std", suggestion="畫面全黑或單色（BLACK_FRAME）：渲染失敗，不能當沒問題", images=imgs), None
    if "id" not in e:
        return vrow(rid, "CAPTURE", "PASS", actual={"mean": float(lum)}, method="mean/std", images=imgs), None
    ida = img(d, e["id"])
    masks = id_masks(ida, man["parts"])
    solo = union(masks)
    n = int(solo.sum())
    frac = n / (w * h)
    notes.update(solo_px=n, frac=round(frac, 4))
    if frac < MIN_FRAC:
        return vrow(rid, "CAPTURE", "UNKNOWN", actual=notes, method="id mask coverage",
                    suggestion="建築不在畫面內（NOT_IN_FRAME）", images=imgs + [e["id"]]), None
    edge = solo[0, :].any() or solo[-1, :].any() or solo[:, 0].any() or solo[:, -1].any()
    notes["clipped"] = bool(edge)
    vis = None
    if e.get("hidden"):
        hid = img(d, e["hidden"])
        diff = np.abs(a - hid).max(axis=2) > DIFF_TOL
        seen = diff & solo
        notes["visible_ratio_diff"] = round(float(seen.sum() / max(1, n)), 4)
        if e.get("vis") and os.path.exists(os.path.join(d, e["vis"])):
            vm = union(id_masks(img(d, e["vis"]), man["parts"]))  # 深度正確（其他幾何塗黑仍會擋）
            notes["visible_ratio_depth"] = round(float((vm & solo).sum() / max(1, n)), 4)
            seen = seen | (vm & solo)
        vis = float(seen.sum() / max(1, n))
        notes["visible_ratio"] = round(vis, 4)
    status, sug = "PASS", ""
    if edge:
        status, sug = "UNKNOWN", "建築被畫面邊緣裁切（CLIPPED）：重要構件可能不在畫面裡"
    elif vis is not None and vis < OCCLUDED:
        status, sug = "UNKNOWN", f"建築被其他物件遮住 {1 - vis:.0%}（OCCLUDED）：這個視角不能用來判定"
    elif vis is not None and vis < PARTIAL:
        status, sug = "WARN", f"部分遮擋：可見 {vis:.0%}"
    return vrow(rid, "CAPTURE", status, actual=notes, expected={"visible_ratio": f">={OCCLUDED}", "clipped": False},
                method="id mask ∩（隱藏目標色差 ∪ 深度正確可見遮罩）", suggestion=sug, images=imgs + [e["id"]],
                camera=e["camera"]), (masks, solo)


# ─────────────────────────── 量測 ───────────────────────────

VIEW_DIMS = {"front": ("right", "up"), "back": ("right", "up"), "left": ("front", "up"), "right": ("front", "up"),
             "top": ("right", "front")}
AXIS_I = {"right": 0, "up": 1, "front": 2}


def silhouette_scale(man, e, solo):
    """正交剪影寬高（公尺）vs 幾何緊貼盒：驗證相機取景／投影沒有算錯（不一致時後面的視覺量測都不可信）。"""
    b = bbox(solo)
    if b is None or e.get("projection") != "ortho" or e["view"] not in VIEW_DIMS:
        return None
    s = e["m_per_px"]
    wm, hm = (b[2] - b[0] + 1) * s, (b[3] - b[1] + 1) * s
    size = man["frame"]["size_rfu"]
    ax_w, ax_h = VIEW_DIMS[e["view"]]
    ew, eh = size[AXIS_I[ax_w]], size[AXIS_I[ax_h]]
    tol_w, tol_h = 2 * s + 0.01 * ew, 2 * s + 0.01 * eh
    ok = abs(wm - ew) <= tol_w and abs(hm - eh) <= tol_h
    return vrow(f"VIS_SCALE:{e['view']}", "VIS_SCALE", "PASS" if ok else "FAIL",
                expected={"width_m": ew, "height_m": eh}, actual={"width_m": round(wm, 4), "height_m": round(hm, 4)},
                deviation={"width": round(wm - ew, 4), "height": round(hm - eh, 4)}, tol={"width": tol_w, "height": tol_h},
                method=f"ortho silhouette bbox × {s*1000:.2f} mm/px vs geometry box ({ax_w}×{ax_h})",
                suggestion="" if ok else "剪影尺寸與幾何不符：相機或縮放資料錯誤，這張圖的量測不可信",
                images=[e["id"]], camera=e["camera"])


def symmetry(man, e, solo):
    """正視剪影對建築中軸鏡射的 IoU；中軸＝建築原點投影（不是剪影中心，刻意不對稱才量得出來）。"""
    if e["view"] != "front" or e.get("projection") != "ortho" or not e.get("px_origin"):
        return None
    ax = e["px_origin"][0]
    h, w = solo.shape
    xs = np.arange(w)
    mx = np.round(2 * ax - xs).astype(int)
    valid = (mx >= 0) & (mx < w)
    mir = np.zeros_like(solo)
    mir[:, valid] = solo[:, mx[valid]]
    inter = (solo & mir).sum()
    uni = (solo | mir).sum()
    iou = float(inter / max(1, uni))
    ys, xs2 = np.nonzero(solo)
    cx = (xs2.mean() - ax) * e["m_per_px"]
    b = bbox(solo)
    left, right = (ax - b[0]) * e["m_per_px"], (b[2] - ax) * e["m_per_px"]
    return {"iou": round(iou, 4), "centroid_offset_m": round(float(cx), 4), "extent_left_m": round(left, 4),
            "extent_right_m": round(right, 4)}


def part_centroid_rfu(man, e, mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    h, w = mask.shape
    dv = px_to_world_delta(e, xs.mean() - w / 2, ys.mean() - h / 2)
    world = np.array(e["camera"]["origin"]) + dv
    return to_rfu(man["frame"], world - np.array(man["frame"]["origin"]))


def gap_between(man, e, ma, mb):
    """A 在上、B 在下（沿影像向上＝相機 y）：逐欄量 A 底到 B 頂的像素距離。"""
    y = np.array(e["camera"]["y"])
    up_dot = float(np.dot(y, man["frame"]["up"]))
    if abs(up_dot) < 0.9:
        return None
    a, b = (ma, mb) if up_dot > 0 else (ma[::-1], mb[::-1])
    cols = np.nonzero(a.any(0) & b.any(0))[0]
    gaps = []
    for c in cols:
        ra = np.nonzero(a[:, c])[0]
        rb = np.nonzero(b[:, c])[0]
        below = rb[rb >= ra.max()]
        if len(below):
            gaps.append(int(below.min()) - int(ra.max()) - 1)
    if not gaps:
        return None
    g = np.array(gaps)
    s = e["m_per_px"]
    return {"columns": int(len(g)), "median_px": float(np.median(g)), "max_px": int(g.max()), "min_px": int(g.min()),
            "median_m": float(max(0.0, np.median(g)) * s), "resolution_m": s}


# ─────────────────────────── 影像輸出 ───────────────────────────

def _font(size=16):
    for p in (r"C:\Windows\Fonts\msjh.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\arial.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def annotate(d, e, label_lines, boxes=(), out_name=None):
    """標註圖：另存 *_annot.png，原始渲染不動（影像比較用原圖）。"""
    im = Image.open(os.path.join(d, e["file"])).convert("RGB")
    dr = ImageDraw.Draw(im)
    for (x0, y0, x1, y1), col in boxes:
        dr.rectangle([x0, y0, x1, y1], outline=col, width=2)
    if e.get("px_point"):
        x, y = e["px_point"]
        dr.ellipse([x - 14, y - 14, x + 14, y + 14], outline=(255, 40, 40), width=3)
    f = _font(18)
    y = 8
    for t in label_lines:
        dr.rectangle([6, y - 2, 12 + dr.textlength(t, font=f), y + 22], fill=(0, 0, 0))
        dr.text((10, y), t, fill=(255, 255, 120), font=f)
        y += 26
    name = out_name or e["file"].replace(".png", "_annot.png")
    im.save(os.path.join(d, name))
    return name


def sheet(d, files, labels, out, cols=3, tile=(640, 360)):
    if not files:
        return None
    rows = math.ceil(len(files) / cols)
    sh = Image.new("RGB", (tile[0] * cols, tile[1] * rows), (24, 24, 24))
    f = _font(20)
    for i, (fn, lb) in enumerate(zip(files, labels)):
        im = Image.open(os.path.join(d, fn)).convert("RGB").resize(tile)
        dr = ImageDraw.Draw(im)
        y0 = tile[1] - 30   # 標籤放底部，不蓋住標註圖左上的量測文字
        dr.rectangle([0, y0, 8 + dr.textlength(lb, font=f), tile[1]], fill=(0, 0, 0))
        dr.text((4, y0 + 3), lb, fill=(255, 255, 255), font=f)
        sh.paste(im, ((i % cols) * tile[0], (i // cols) * tile[1]))
    sh.save(os.path.join(d, out), quality=88)
    return out


# ─────────────────────────── E 參考圖比較 ───────────────────────────

def ref_mask(spec):
    im = Image.open(spec["image"])
    mode = (spec.get("mask") or {}).get("mode", "alpha" if im.mode in ("RGBA", "LA") else "bg")
    if mode == "alpha":
        return np.asarray(im.convert("RGBA"))[:, :, 3] > 127
    a = np.asarray(im.convert("RGB")).astype(np.int16)
    bg = np.array((spec.get("mask") or {}).get("bg") or a[0, 0])
    tol = (spec.get("mask") or {}).get("tol", 24)
    return np.abs(a - bg).max(axis=2) > tol


def _norm_sil(m, height=400):
    b = bbox(m)
    crop = m[b[1]:b[3] + 1, b[0]:b[2] + 1]
    h, w = crop.shape
    nw = max(1, int(round(w * height / h)))
    im = Image.fromarray((crop * 255).astype(np.uint8)).resize((nw, height), Image.NEAREST)
    return np.asarray(im) > 127


def compare_reference(spec, model_mask, model_view):
    """剪影比較（正交、同視角才算分數；否則 UNKNOWN，不給誤導分數）。
    校正：兩邊都裁到剪影外框、縮放到同高、底邊中點對齊（正交投影下這是唯一允許的相似變換）。"""
    need = {"view": spec.get("view"), "projection": spec.get("projection")}
    if not spec.get("approved"):
        return vrow("REF_COMPARE", "REFERENCE", "UNKNOWN", expected="approved reference",
                    actual={"approved": spec.get("approved")}, method="—",
                    suggestion="參考圖沒有標記為已確認（approved），不拿來當標準答案", section="visual")
    if need["projection"] != "ortho" or need["view"] != model_view.get("view") or model_view.get("projection") != "ortho":
        return vrow("REF_COMPARE", "REFERENCE", "UNKNOWN", expected={"view": model_view.get("view"), "projection": "ortho"},
                    actual=need, method="calibration precheck",
                    suggestion="參考圖與模型視角／投影不一致，未校正前不計算相似度（避免誤導分數）")
    rm = ref_mask(spec)
    a, b = _norm_sil(model_mask), _norm_sil(rm)
    W = max(a.shape[1], b.shape[1])
    pa = np.zeros((a.shape[0], W), bool)
    pb = np.zeros((b.shape[0], W), bool)
    pa[:, (W - a.shape[1]) // 2:(W - a.shape[1]) // 2 + a.shape[1]] = a
    pb[:, (W - b.shape[1]) // 2:(W - b.shape[1]) // 2 + b.shape[1]] = b
    iou = float((pa & pb).sum() / max(1, (pa | pb).sum()))
    ar_m, ar_r = a.shape[1] / a.shape[0], b.shape[1] / b.shape[0]
    bands = 20
    prof = []
    for k in range(bands):  # 由下往上
        r0 = pa.shape[0] - (k + 1) * pa.shape[0] // bands
        r1 = pa.shape[0] - k * pa.shape[0] // bands
        wa = pa[r0:r1].any(0).sum() / pa.shape[0]
        wb = pb[r0:r1].any(0).sum() / pb.shape[0]
        prof.append((k, float(wa), float(wb), float(wa - wb)))
    worst = max(prof, key=lambda t: abs(t[3]))
    tol = spec.get("tol", {"iou": 0.9, "aspect": 0.05, "band": 0.06})
    issues = []
    if abs(ar_m - ar_r) / ar_r > tol["aspect"]:
        issues.append(f"寬高比 模型 {ar_m:.3f} vs 參考 {ar_r:.3f}")
    if abs(worst[3]) > tol["band"]:
        lo, hi = worst[0] * 100 // bands, (worst[0] + 1) * 100 // bands
        issues.append(f"高度 {lo}–{hi}% 段寬度差 {worst[3]:+.3f}×高（模型{'較寬' if worst[3] > 0 else '較窄'}）")
    status = "PASS" if iou >= tol["iou"] and not issues else "REVIEW"
    return vrow("REF_COMPARE", "REFERENCE", status, expected={"iou": f">={tol['iou']}", "aspect": ar_r},
                actual={"iou": round(iou, 4), "aspect": round(ar_m, 4), "worst_band": {"band": worst[0], "model_w": worst[1],
                        "ref_w": worst[2], "diff": round(worst[3], 4)}, "profile": [[k, round(x, 4), round(y, 4)] for k, x, y, _ in prof]},
                method="silhouette IoU + bounding ratio + 20-band width profile（底中對齊、等高縮放）",
                suggestion="；".join(issues) + ("。差異需人工確認是否為刻意設計，不自動重建" if issues else ""),
                error_class="STYLE_DEVIATION" if issues else None)
