#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""從角色設定表切出對話用立繪胸像。

背景：reimu / yoriichi 既有的 12 張（2026-09 入庫、使用者已接受）就是設定表
表情格直接切下、等比放大 2 倍的結果，UI 的 Portrait TextureRect 用
expand + keep-aspect 顯示。這支腳本沿用同一條路，不另開 pipeline。

⚠ 本檔的核心教訓（2026-09-17 第四版，使用者驗收打回兩次後定案）：

1. **先隔離人形，再裁框**，不要「先裁框再清雜物」。
   設定表上相鄰的表情格挨得很近，裁框幾乎一定吃到隔壁的頭髮／衣服／手臂。
   舊版靠 CLEAN_TOP 硬寫像素高度去擦，只補到 8 個受污染格中的 5 個，
   換一張來源圖就再度失效。

2. **隔離要用 Voronoi（最近臉指派），不能用 alpha 連通元件。**
   設定表上人物彼此相接，整張圖的 alpha 常常黏成一塊 ——
   「取最大元件」等於整塊留著，「侵蝕切斷」則會把帽簷、髮梢一起咬掉。
   Voronoi 不管相不相接，一律按空間歸屬切開，四張來源圖同一套邏輯就通。

3. **不要用整欄等分切格。**
   慧音右欄的臉距實測 pitch≈254.7，等分卻是 272 —— 五格累積偏移
   -39/-19/-2/+13/+31，第 0 格切掉頭頂、第 4 格吃進上一格下襬。
   這正是使用者看到的兩個症狀。改成偵測臉 → 線性回歸取 pitch → 外插補齊
   cascade 漏掉的格（慧音第 5 格就偵測不到）。

4. **框尺寸用臉寬的固定倍率，全角色共用同一組常數**，
   否則臉在框裡的佔比會從 42% 跳到 65%，換講者時人物忽大忽小。

5. **表情格 = 尺寸最一致的那一群臉，不是「接近中位數」的那群。**
   中位數會被小尺寸誤判（鞋子、鈴鐺、袖口）拉走 —— 實測 kosuzu 的中位數
   從 138 掉到 86，表情格就從 5 個變成 2 個。改成挑「同尺寸同伴最多」的那群。

用法：
    python tools/build_portraits.py --cells            # 切全部格子 + 接觸表
    python tools/build_portraits.py --cells --check    # 附像素斷言（不需視覺模型）
    python tools/build_portraits.py --cells --install "keine:0=normal,3=smile"
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = Path("D:/參考圖概念圖/參考圖文理/立繪角色")
OUT_DIR = ROOT / "godot" / "assets" / "portraits"
WORK_DIR = ROOT / "work" / "portraits"
CASCADE = Path.home() / "AppData/Local/Temp/lbpcascade_animeface.xml"

# 胸像框 —— 全部以「臉寬中位數 m」為單位，相對臉中心定位。
#   上緣 = 臉中心 - TOP·m    下緣 = 臉中心 + BOTTOM·m    左右各 HALF_W·m
# TOP 1.28 是量出來的：各角色頭頂最高超出臉框 0.65m（慧音），
#   再加 0.5m（臉框上半）與 0.13m 餘裕 = 1.28。舊值 1.16 只剩 1.5px，
#   所以慧音的頭頂被切掉。
# BOTTOM 0.75：cascade 的臉框底最深到 0.61m（阿求），加餘裕與一點頸肩。
#   別設成 0.48 —— 那會讓下巴落在框外，五官被截斷。
# 這組值刻意抓寬（長寬比 0.61），保證誰都不會被切；多餘的空白由
# tighten() 逐角色收掉，不要在這裡為了比例而縮框。
TOP, BOTTOM, HALF_W = 1.28, 0.75, 0.615
UPSCALE = 2

# 成品長寬比。UI 的 Portrait TextureRect 錨點框是 190x266（0.715）且
# keep_aspect_centered —— 比它窄的圖會被高度限制，人物在對話框裡縮小一號。
# 已接受的 reimu(0.713) / yoriichi(0.700) 都貼著這個值，新角色必須跟上。
TARGET_ASPECT = 0.710

SHEETS = {
    # 慧音用 慧音-立繪圖.png 右欄 5 格：可用區比舊的 慧音.png 六格大一倍多。
    "keine": "慧音-立繪圖.png",
    "kosuzu": "本居小玲(鈴耐庵).png",
    "akyuu": "稗田阿求.png",
    "miyoi": "奧野田美宵(鯢吞亭).png",
}

# 只在指定 x 範圍內找表情格。慧音那張左半是全身立繪與離身的眼部特寫面板，
# 不限制 ROI 會把主視覺大頭像混進表情欄，格距回歸就歪了。
FACE_ROI_X = {"keine": (790, 10**6)}

# 等距縱列的角色：偵測到的臉做線性回歸取 pitch，再外插補齊漏掉的格。
COLUMN_COUNT = {"keine": 5}

# 下鄰頭頂護欄。框底超過「下一格臉頂緣 − GUARD·m」的部分一律清成透明。
#
# ⚠ 這是 2026-09-17 第五版補的洞（使用者：「有一張圖看到其他的臉」）。
#   阿求 normal 框底 246 已越過下鄰臉頂 270 的頭頂區，切進了下一格的頭，
#   而那塊紫髮**與她自己的衣服下襬相連** —— 所以 audit() 的
#   「alpha 連通元件只有一塊」完全查不到，全綠通過。
#   教訓：污染不一定是孤島。相鄰格在來源圖上本來就會黏在一起，
#   連通元件數是必要條件、不是充分條件，必須另外用幾何界線把下鄰切掉。
#
# GUARD 0.55：下鄰的頭頂最高伸出臉框上緣約 0.65m（慧音），取 0.55 讓護欄
#   落在「頭頂之上」而不是「臉之上」—— 設成 0 會留下半顆頭，設成 1.0 則會
#   反過來吃掉本格自己的肩膀（實測阿求要多裁 54px = 19% 框高）。
BOTTOM_GUARD = 0.55


def imread(path: Path) -> np.ndarray:
    """cv2.imread 讀不了中文路徑（Windows/MSYS），改走 fromfile + imdecode。"""
    img = cv2.imdecode(np.fromfile(str(path), dtype=np.uint8), cv2.IMREAD_UNCHANGED)
    if img is None:
        raise SystemExit(f"讀不到圖：{path}")
    return img


def imwrite(path: Path, img: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ok, buf = cv2.imencode(".png", img)
    if not ok:
        raise SystemExit(f"編碼失敗：{path}")
    buf.tofile(str(path))


def _gray(img: np.ndarray) -> np.ndarray:
    if img.shape[2] == 4:
        a = img[..., 3:4] / 255.0
        rgb = (img[..., :3] * a + 255 * (1 - a)).astype(np.uint8)
    else:
        rgb = img[..., :3]
    return cv2.equalizeHist(cv2.cvtColor(rgb, cv2.COLOR_BGR2GRAY))


def detect_faces(img: np.ndarray, roi_x: tuple[int, int] | None = None) -> list[tuple[int, int, int, int]]:
    """多組參數掃臉後去重。回傳 (x, y, w, h) 清單。"""
    cascade = cv2.CascadeClassifier(str(CASCADE))
    if cascade.empty():
        raise SystemExit(f"載不到 cascade：{CASCADE}（先下載 lbpcascade_animeface.xml）")
    gray = _gray(img)
    found: list[tuple[int, int, int, int]] = []
    for scale in (1.02, 1.03, 1.05, 1.08):
        for neighbours in (2, 3, 4):
            found += [tuple(int(v) for v in f)
                      for f in cascade.detectMultiScale(gray, scale, neighbours, minSize=(40, 40))]
    if roi_x is not None:
        found = [f for f in found if roi_x[0] <= f[0] <= roi_x[1]]
    kept: list[tuple[int, int, int, int]] = []
    for face in sorted(found, key=lambda f: -f[2]):
        cx, cy = face[0] + face[2] / 2, face[1] + face[3] / 2
        if any(abs(cx - (k[0] + k[2] / 2)) < k[2] * 0.5 and abs(cy - (k[1] + k[3] / 2)) < k[3] * 0.5
               for k in kept):
            continue
        kept.append(face)
    return kept


def grid_faces(faces: list[tuple[int, int, int, int]]) -> list[tuple[int, int, int, int]]:
    """表情格 = 尺寸最一致的那一群。

    不要用「接近中位數」—— 中位數會被小尺寸誤判（鞋子／鈴鐺／袖口）拉走，
    實測 kosuzu 的中位數從 138 掉到 86，表情格就從 5 個剩 2 個。

    分群後還要再砍掉明顯偏大的：設定表通常在角落擺一顆主視覺大頭，
    它跟表情格差距沒大到會被 0.78–1.28 濾掉（阿求 177 vs 中位數 141），
    但整個人形塞滿畫面，切出來是張沒用的大臉特寫。
    """
    if len(faces) < 2:
        return faces
    best, best_key = faces, (0, 0)
    for f in faces:
        w = f[2]
        group = [g for g in faces if 0.78 * w <= g[2] <= 1.28 * w]
        key = (len(group), w)          # 同伴最多者勝；平手取較大的（排掉小誤判群）
        if key > best_key:
            best, best_key = group, key
    med = float(np.median([f[2] for f in best]))
    return [f for f in best if f[2] <= 1.2 * med]


def column_faces(faces: list[tuple[int, int, int, int]], count: int) -> list[tuple[int, int, int, int]]:
    """等距縱列：回歸 pitch 後外插補齊漏掉的格。

    直接等分欄高是錯的 —— 慧音實測 pitch 254.7、等分卻給 272，
    五格累積偏移 ±35px（≈13% 格高），頭頂與下襬就是這樣被切到的。
    """
    if len(faces) < 2:
        return faces
    ordered = sorted(faces, key=lambda f: f[1])
    centers = [f[1] + f[3] / 2.0 for f in ordered]
    pitch, c0 = np.polyfit(range(len(centers)), centers, 1)
    fw = int(round(float(np.median([f[2] for f in ordered]))))
    fx = int(round(float(np.median([f[0] + f[2] / 2.0 for f in ordered])) - fw / 2.0))
    return [(fx, int(round(c0 + pitch * i - fw / 2.0)), fw, fw) for i in range(count)]


def partition(img: np.ndarray, seeds: list[tuple[int, int, int, int]]) -> np.ndarray:
    """最近臉指派（Voronoi）：每個不透明像素歸給距離最近的臉中心。

    設定表上人物彼此相接，alpha 連通元件會整片黏在一起；Voronoi 不管
    相不相接，一律按空間歸屬切開 —— 這是四張來源圖唯一都通的隔離法。

    ⚠ 距離要除以臉寬再比。設定表上主視覺人物又大又高，用絕對距離的話
    它的裙襬／長髮會「贏過」旁邊小格自己的身體，被判給小格變成殘片
    （實測 kosuzu[4] 右緣就多出一條 3% 的布料）。除以臉寬 = 大人物有
    大的勢力範圍，小格只拿自己身邊那圈。
    """
    h, w = img.shape[:2]
    ys, xs = np.nonzero(img[..., 3] > 8)
    c = np.array([[f[0] + f[2] / 2.0, f[1] + f[3] / 2.0] for f in seeds], float)
    scale = np.array([float(f[2]) for f in seeds])
    d = ((xs[:, None] - c[None, :, 0]) ** 2 + (ys[:, None] - c[None, :, 1]) ** 2) / scale[None, :] ** 2
    lab = np.full((h, w), -1, np.int32)
    lab[ys, xs] = d.argmin(1)
    return lab


def isolate(img: np.ndarray, lab: np.ndarray, k: int,
            face: tuple[int, int, int, int]) -> np.ndarray:
    """取第 k 塊 Voronoi 區域裡「含臉中心」的那個連通元件，其餘全部清成透明。"""
    if img.shape[2] != 4:
        return img
    mask = (lab == k).astype(np.uint8)
    count, comp = cv2.connectedComponents(mask)
    if count > 1:
        fx, fy, fw, fh = face
        cy, cx = fy + fh // 2, fx + fw // 2
        c = int(comp[cy, cx]) if 0 <= cy < comp.shape[0] and 0 <= cx < comp.shape[1] else 0
        if c == 0:
            box = comp[max(0, fy):fy + fh, max(0, fx):fx + fw]
            vals = box[box > 0]
            if vals.size:
                c = int(np.bincount(vals).argmax())
        if c:
            mask = (comp == c).astype(np.uint8)
    out = img.copy()
    out[mask == 0] = 0
    return out


def clip_below(layer: np.ndarray, face: tuple[int, int, int, int],
               seeds: list[tuple[int, int, int, int]], m: int) -> np.ndarray:
    """把「下一格的頭」整段清成透明。

    Voronoi 是按「最近臉中心」分區的，分界線落在兩張臉的**中間**；
    但下一格的頭頂比它的臉中心還高得多，這段頭髮離本格臉中心更近，
    於是被判給本格、跟著本格的衣服下襬一起留下來。
    使用者看到的「其他的臉」就是這樣來的（阿求 normal 底部那顆紫髮頭）。

    ⚠ 它與本格主體是**相連**的，所以 audit() 的連通元件檢查永遠是 1 塊、
      永遠全綠。幾何界線是唯一擋得住的手段。
    """
    if layer.shape[2] != 4:
        return layer
    fcx = face[0] + face[2] / 2.0
    fcy = face[1] + face[3] / 2.0
    below = [g for g in seeds
             if abs((g[0] + g[2] / 2.0) - fcx) < face[2] * 0.8
             and (g[1] + g[3] / 2.0) > fcy + face[3] * 0.5]
    if not below:
        return layer
    limit = int(round(min(g[1] for g in below) - BOTTOM_GUARD * m))
    if limit >= layer.shape[0]:
        return layer
    out = layer.copy()
    out[max(0, limit):] = 0
    return out


def frame_for(face: tuple[int, int, int, int], m: int) -> tuple[int, int, int, int]:
    """以臉中心對齊固定框。全角色共用同一組比例，臉的佔比才會一致。"""
    cx = face[0] + face[2] / 2.0
    cy = face[1] + face[3] / 2.0
    w = int(round(2 * HALF_W * m))
    h = int(round((TOP + BOTTOM) * m))
    # ⚠ 不要把超出畫布的框夾回邊界：最上一格的框本來就會超出上緣，
    #   夾回去等於把頭頂裁掉、臉在框裡的位置也跟著下移（切換時人物上下跳）。
    return (int(round(cx - HALF_W * m)), int(round(cy - TOP * m)), w, h)


def crop(img: np.ndarray, cell: tuple[int, int, int, int]) -> np.ndarray:
    """切一格並放大。超出畫布處補透明（RGBA）或補背景色（RGB）。"""
    x, y, w, h = cell
    ih, iw = img.shape[:2]
    pad_l, pad_t = max(0, -x), max(0, -y)
    pad_r, pad_b = max(0, x + w - iw), max(0, y + h - ih)
    tile = img[max(0, y):min(ih, y + h), max(0, x):min(iw, x + w)]
    if tile.shape[2] == 4:
        out = tile
        if pad_l or pad_t or pad_r or pad_b:
            out = cv2.copyMakeBorder(out, pad_t, pad_b, pad_l, pad_r,
                                     cv2.BORDER_CONSTANT, value=[0, 0, 0, 0])
        return cv2.resize(out, (w * UPSCALE, h * UPSCALE), interpolation=cv2.INTER_LANCZOS4)
    rgb = tile[..., :3]
    flat = rgb.reshape(-1, 3)
    colours, counts = np.unique(flat[::7], axis=0, return_counts=True)
    bg = colours[counts.argmax()]
    if pad_l or pad_t or pad_r or pad_b:
        rgb = cv2.copyMakeBorder(rgb, pad_t, pad_b, pad_l, pad_r,
                                 cv2.BORDER_CONSTANT, value=[int(v) for v in bg])
    return cv2.resize(rgb, (w * UPSCALE, h * UPSCALE), interpolation=cv2.INTER_LANCZOS4)


def tighten(tiles: list[np.ndarray]) -> list[np.ndarray]:
    """同角色一起收緊到 TARGET_ASPECT。

    frame_for() 的 TOP/BOTTOM 刻意抓寬（長寬比 0.61）以遷就頭頂最高的慧音，
    但 kosuzu 只需 0.43m、miyoi 只需 0.37m —— 全體共用等於替所有人加上
    不必要的空白，在 UI 的 keep_aspect_centered 下會被高度限制而縮小一號。

    ⚠ 一定要用「該角色所有格的 alpha union」而不是逐格自己的 bbox：
    逐格收會讓每張圖的臉落在不同位置，換表情時人物上下跳。
    """
    boxes = []
    for t in tiles:
        if t.shape[2] != 4:
            return tiles
        ys, xs = np.nonzero(t[..., 3] > 8)
        if xs.size == 0:
            return tiles
        boxes.append((xs.min(), ys.min(), xs.max(), ys.max()))
    l = min(b[0] for b in boxes)
    top = min(b[1] for b in boxes)
    r = max(b[2] for b in boxes)
    b_ = max(b[3] for b in boxes)
    h, w = tiles[0].shape[:2]
    # 先收到 union，再對稱補回 TARGET_ASPECT（補的是透明，不會生出內容）
    cw, chh = r - l + 1, b_ - top + 1
    if cw / chh > TARGET_ASPECT:
        need_h = int(round(cw / TARGET_ASPECT))
        pad = need_h - chh
        top = max(0, top - pad // 2)
        b_ = min(h - 1, b_ + (pad - pad // 2))
    else:
        need_w = int(round(chh * TARGET_ASPECT))
        pad = need_w - cw
        l = max(0, l - pad // 2)
        r = min(w - 1, r + (pad - pad // 2))
    return [t[top:b_ + 1, l:r + 1] for t in tiles], (int(l), int(top))


def keep_face_blob(tile: np.ndarray, face_in_tile: tuple[int, int, int, int]) -> np.ndarray:
    """裁框後再清一次：只留含臉的那塊。

    為什麼隔離過還要再清一次 —— 隔離是在整張來源圖上做的，那時裙襬／長髮
    與主體是**同一個**連通元件，合法保留。但裁框把中間那段切掉後，殘留的
    末端就變成孤島（實測 kosuzu[4] 右緣那條 3% 布料就是這樣來的）。
    所以連通性必須在最終畫布上重新判定。
    """
    if tile.shape[2] != 4:
        return tile
    mask = (tile[..., 3] > 8).astype(np.uint8)
    count, comp = cv2.connectedComponents(mask)
    if count <= 2:
        return tile
    fx, fy, fw, fh = face_in_tile
    cy = min(max(fy + fh // 2, 0), comp.shape[0] - 1)
    cx = min(max(fx + fw // 2, 0), comp.shape[1] - 1)
    c = int(comp[cy, cx])
    if c == 0:
        box = comp[max(0, fy):fy + fh, max(0, fx):fx + fw]
        vals = box[box > 0]
        if vals.size == 0:
            return tile
        c = int(np.bincount(vals).argmax())
    out = tile.copy()
    out[comp != c] = 0
    return out


def audit(tile: np.ndarray, face_in_tile: tuple[int, int, int, int]) -> tuple[bool, str]:
    """像素斷言 —— 使用者的兩個抱怨都機械化可驗，不需要任何視覺模型。

    「多出其他圖案」= 面積 >1% 的 alpha 連通元件超過一個。
    「切到人臉」   = 臉框（含頭頂）貼到框緣。

    ⚠ 不要驗「整個人形四周留白」：使用者已接受的 reimu / yoriichi 12 張
    量出來全是 top=0 / L=0 / R=0 —— 肩膀出血是這種胸像的正常構圖，
    拿留白當標準會把合格品判成不合格。
    """
    if tile.shape[2] != 4:
        return True, "RGB（無 alpha 可驗）"
    mask = (tile[..., 3] > 8).astype(np.uint8)
    total = mask.size
    count, _, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    blobs = [i for i in range(1, count) if stats[i, cv2.CC_STAT_AREA] > total * 0.01]
    fx, fy, fw, fh = face_in_tile
    problems = []
    if len(blobs) != 1:
        problems.append(f"殘片 {len(blobs)} 塊")
    if fx < 8 or tile.shape[1] - (fx + fw) < 8:
        problems.append(f"臉貼左右緣 {fx}/{tile.shape[1] - fx - fw}px")
    # 頭頂：只看臉的 x 範圍正上方那一條，不看肩膀
    col = mask[:, max(0, fx):fx + fw]
    rows = np.nonzero(col.sum(1) > 0)[0]
    head_top = int(rows[0]) if rows.size else 0
    if head_top < 6:
        problems.append(f"頭頂留白 {head_top}px")
    if fy + fh > tile.shape[0]:
        problems.append("下巴超出框")
    return (not problems), ("OK" if not problems else "、".join(problems))


def contact_sheet(tiles: list[tuple[str, np.ndarray]], cols: int = 6) -> np.ndarray:
    cw, ch = 230, 340
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.full((rows * (ch + 36), cols * cw, 3), 38, np.uint8)
    for i, (label, tile) in enumerate(tiles):
        r, c = divmod(i, cols)
        scale = min((cw - 14) / tile.shape[1], ch / tile.shape[0])
        small = cv2.resize(tile, (int(tile.shape[1] * scale), int(tile.shape[0] * scale)))
        if small.shape[2] == 4:
            # 接觸表是 RGB；只在預覽合成深灰底，安裝檔仍保留透明。
            alpha = small[..., 3:4].astype(np.float32) / 255.0
            small = (small[..., :3] * alpha + 34 * (1.0 - alpha)).astype(np.uint8)
        y0 = r * (ch + 36)
        x0 = c * cw + (cw - small.shape[1]) // 2
        sheet[y0:y0 + small.shape[0], x0:x0 + small.shape[1]] = small
        cv2.putText(sheet, label, (c * cw + 10, y0 + ch + 25),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.62, (235, 235, 235), 1, cv2.LINE_AA)
    return sheet


def build(cid: str, filename: str):
    """回傳 [(來源臉框, tile, tile 內的臉框)]，順序 = 由上而下、由左而右。"""
    img = imread(SRC_DIR / filename)
    cells = detect_faces(img, FACE_ROI_X.get(cid))
    cells = column_faces(cells, COLUMN_COUNT[cid]) if cid in COLUMN_COUNT else grid_faces(cells)
    if not cells:
        return []
    # 種子要含「整張圖所有的臉」（包含主視覺大頭像），否則主視覺那塊會被
    # 表情格搶走像素，蓋在胸像上變成殘片。
    seeds = list(detect_faces(img))
    for f in cells:
        if not any(abs(f[0] - s[0]) < s[2] * 0.4 and abs(f[1] - s[1]) < s[3] * 0.4 for s in seeds):
            seeds.append(f)
    lab = partition(img, seeds)

    m = int(round(float(np.median([f[2] for f in cells]))))
    row = int((TOP + BOTTOM) * m) // 2
    cells.sort(key=lambda f: ((f[1] + f[3] // 2) // row, f[0]))
    faces, tiles, fits = [], [], []
    for face in cells:
        k = min(range(len(seeds)),
                key=lambda i: (seeds[i][0] - face[0]) ** 2 + (seeds[i][1] - face[1]) ** 2)
        # 先隔離人形，再裁框 —— 順序反過來就得靠硬寫像素擦雜物，永遠在打補丁。
        layer = isolate(img, lab, k, face)
        # Voronoi 擋不住「下一格的頭頂」：它比下鄰的臉中心更靠近本格，
        # 會被判給本格並黏在本格衣襬上。必須再用幾何界線砍一刀。
        layer = clip_below(layer, face, seeds, m)
        cell = frame_for(face, m)
        tile = crop(layer, cell)
        fit = (int((face[0] - cell[0]) * UPSCALE), int((face[1] - cell[1]) * UPSCALE),
               face[2] * UPSCALE, face[3] * UPSCALE)
        # 裁框會把長髮／裙襬的中段切掉，留下的末端變成孤島 —— 連通性必須在
        # 最終畫布上重判一次，只在來源圖隔離是不夠的。
        faces.append(face)
        tiles.append(keep_face_blob(tile, fit))
        fits.append(fit)
    # 切頭必須在「收緊前」驗：收緊會裁到 alpha union，上緣本來就會貼邊。
    # 已接受的 reimu / yoriichi 量出來上緣貼邊都是 100% 寬 —— 拿收緊後的圖
    # 驗頭頂留白，等於把合格品判成不合格。
    audits = [audit(t, f) for t, f in zip(tiles, fits)]
    # 收緊必須在全部切完後一起做（要用同角色的 alpha union），
    # 而且臉框座標要跟著位移，否則後續對位會錯。
    tight, (dx, dy) = tighten(tiles)
    fits = [(f[0] - dx, f[1] - dy, f[2], f[3]) for f in fits]
    return list(zip(faces, tight, fits, audits))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cells", action="store_true", help="切全部格子與接觸表到 work/portraits/")
    ap.add_argument("--check", action="store_true", help="對每格跑像素斷言（殘片／切臉）")
    ap.add_argument("--install", default="", help="character:index=state[,...];... 寫入 assets/portraits/")
    args = ap.parse_args()

    install: dict[str, dict[int, str]] = {}
    for chunk in filter(None, args.install.split(";")):
        cid, _, pairs = chunk.partition(":")
        install.setdefault(cid, {})
        for pair in filter(None, pairs.split(",")):
            idx, _, state = pair.partition("=")
            install[cid][int(idx)] = state

    tiles: list[tuple[str, np.ndarray]] = []
    failures = 0
    for cid, filename in SHEETS.items():
        cells = build(cid, filename)
        print(f"== {cid}  {filename}  cells={len(cells)}")
        for i, (face, tile, fit, verdict) in enumerate(cells):
            # ⚠ 切法一改，index→表情 的對應就會漂移，而且不會報錯。
            #   永遠印出來源座標讓人核對，不要盲目沿用舊的 --install 字串。
            line = f"   [{i}] face=({face[0]},{face[1]},{face[2]}) -> {tile.shape[1]}x{tile.shape[0]}"
            if args.check:
                ok, why = verdict
                failures += 0 if ok else 1
                line += f"  {'OK  ' if ok else 'FAIL'} {why}"
            print(line)
            if args.cells:
                imwrite(WORK_DIR / f"{cid}_cell{i}.png", tile)
                tiles.append((f"{cid}[{i}]", tile))
            state = install.get(cid, {}).get(i)
            if state:
                imwrite(OUT_DIR / f"{cid}_{state}.png", tile)
                print(f"        installed {cid}_{state}.png")
    if args.cells:
        out = WORK_DIR / "contact.png"
        imwrite(out, contact_sheet(tiles))
        print(f"接觸表：{out}")
    if args.check:
        print(f"[AUDIT] failures={failures}")
        return 1 if failures else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
