# arch_spatial — 建築構件空間驗證（P0：座標／BVHTree 連接／約束）

共用核心：`tools/blender/arch_spatial.py`（Blender 內執行，**唯讀**：不改物件、不存 .blend）。
CLI：`tools/blender/arch_check.py`。回歸：`tools/blender/test_arch_spatial.py`。
Blender↔Godot 軸向實測：`godot/tools/arch_glb_probe.gd`。

```bash
B="D:/Blender/blender-5.2.1-windows-x64/blender.exe"
# 有連接表
"$B" -b asset.blend --python tools/blender/arch_check.py -- --map=x.arch.json [--out=r.json] [--cache=c.json] [--undeclared=warn|fail|off]
# 沒有連接表（Tripo GLB 等）：懸空零件＋未宣告穿插；--split 拆連通島；--scale 換成遊戲內尺寸再量
"$B" -b --factory-startup --python tools/blender/arch_check.py -- --glb=x.glb --scan --split --scale=3.2
# 座標／尺寸／OBB 報告
"$B" -b asset.blend --python tools/blender/arch_check.py -- --transforms [--objects=a,b]
# 回歸（約 11 秒，含 393 物件效能案例）＋軸向實測
"$B" -b --factory-startup --python tools/blender/test_arch_spatial.py -- --glb-out=<dir>
godot --headless --path godot --script res://tools/arch_glb_probe.gd -- --glb=<dir>/arch_axis_test.glb --expect=<dir>/arch_axis_test.expect.json
```
exit：有 FAIL → 1；只有 UNKNOWN → 3；其他 0。

## 連接表格式（`*.arch.json`）

```json
{
  "building_id": "s01_torii_a", "style": "japanese_shrine",
  "frame": {"origin": "MARK_Origin" | [x,y,z], "front": "MARK_Front" | "-Y" | "local:-Y@root"},
  "components": {"torii": {"object": "s01_torii_a", "type": "gate", "role": "structure"}},
  "constraints": [
    {"id": "torii_on_base", "type": "SUPPORT", "a": "torii", "b": "base", "embed_max": 0.03, "priority": "hard"}
  ],
  "sample_step": null, "check_detached": true
}
```
- `frame`：建築自身座標。`right = front × up`（建築面朝 front 時自己的右手）；左右／前後一律用這個，不用世界 X/Y。預設 front = Blender −Y = Godot +Z。
- 容差：`tol`（公尺，角度為度）、`tol_rel`（× 兩構件最小尺寸，取大者）。`priority: soft` 違反時記 WARN。
- 構件只認明確的物件名／components 對應，不從名稱猜用途。

| type | a / b 意義 | 量法 | 主要參數 |
|---|---|---|---|
| SUPPORT | a 由 b 支撐 | 封閉網格：雙向射線＋先判內外；非封閉：最低帶頂點上下最近面 | `embed_max` 0.01、`min_contact` 0.7、`require` either/a/b、`contact_band` |
| CONTACT | 應貼合 | 雙向取樣 → `find_nearest`；相交時量穿透深度 | `tol` 0.002、`allow_depth` |
| SNAP | 模組對接 | 有 `anchor_a/anchor_b`：錨點距離；否則接縫間隙分布＋面反向平行 | `angle_tol` 2° |
| OVERLAP_ALLOWED | 榫接／屋瓦搭接 | 穿透取樣點必須在 `region`（物件或 min/max）內，深度 ≤ `max_depth`；分開則 FAIL（`must_touch`） | `region`、`max_depth` |
| CLEARANCE_REQUIRED | 門扇／通道淨距 | 最小距離在 [min, max] | `min`、`max` |
| NO_INTERSECTION | 不得穿插 | 穿透深度（共面接觸不算） | `tol` 0.001 |
| SYMMETRIC | a 鏡射 ≈ b（a=b 為自身對稱） | 鏡射取樣 → `find_nearest` p95＋重心差 | `plane: {point: 構件名|[x,y,z], normal: "x"|"right"|[...]}` |
| PARALLEL / PERPENDICULAR | 軸向 | `acos(|a·b|)` | `axis_a/axis_b`：`local:Z`、`frame:up`、`world:X`、`obb:long` |
| COAXIAL | 中心線對齊（屋頂對主體） | b 中心到 a 軸線距離（建築座標分量） | `axis`、`center` aabb/centroid |
| CONTINUOUS | `components` 有序清單（石階） | 頂高級差一致＋相鄰接縫 | `rise_max`、`gap_tol` |
| EVEN_SPACING | `components`（柱列）| 中心投影間距相對偏差（預設 soft） | `axis` |

另外每次都會跑：**DETACHED**（接觸圖從最低構件洪水填充，連不到地面的零件 = 懸空）與**未宣告穿插**（AABB 只當候選，BVH 確認；非封閉網格的相交彙總成一列 UNKNOWN）。

每列結果：`rule_id, type, building_id, object_ids, status, priority, severity, expected, actual, deviation, tolerance, method, suggestion, evidence, fix`。`fix` 只是建議的最小平移（不會自動套用）。

## 可信度邊界（實測）
- BVH `overlap()` 只證明三角形相交；穿透深度需要至少一方是封閉網格。兩方都不封閉 → UNKNOWN。
- 穿透深度解析度 ≈ 取樣步距（預設 min(0.05, 最小尺寸/4)）；平行面間隙是精確值。
- 快取鍵 = 工具版本＋約束＋建築座標＋所有相關構件的**世界評估後網格**雜湊：頂點、修改器、Transform、Parent 任一變動都失效。
- Blender→Godot 軸向 `(x, y, z) → (x, z, −y)` 已由實際匯出 GLB 讀回驗證（Parent、非均勻、負縮放，偏差 0.000000 m）。
- Tripo 單網格（例：手水舍 186,899 面）拆成 1,815 個非封閉島：懸空可判，穿插只能 UNKNOWN。
