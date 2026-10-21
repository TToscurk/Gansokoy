# arch_spatial — 建築構件空間驗證（P0 座標／BVHTree 連接／約束 ＋ P1 一致性／Scene Graph／道路排列／修正預覽）

| 檔案 | 角色 |
|---|---|
| `tools/blender/arch_spatial.py` | 共用幾何核心（Blender 內執行，**唯讀**：不改物件、不存 .blend）：座標／OBB、BVH 接觸穿插支撐、約束、Scene Graph、修正預覽 |
| `tools/blender/arch_check.py` | CLI |
| `tools/blender/test_arch_spatial.py` | Blender 端回歸（約 10 秒） |
| `godot/tools/arch_spatial_lib.gd` | Godot 端共用庫：GLB 原始資料 vs 匯入（Phase 7）、道路排列（Phase 5）、同一份結果欄位 |
| `godot/tools/arch_glb_probe.gd` | Blender 期望值 vs GLB（headless） |
| `godot/tools/test_arch_spatial_lib.gd` | Godot 庫單元測試（headless，合成資料） |
| `godot/tools/fastlane/place_building.gd` | 快速通道：原三項＋第 4 項 `layout`＋`consistency` |
| `godot/tools/fastlane/test_fastlane_arch.py` | 快速通道整合測試（真的 village_v2，`--dry --no-shots`，跑完自動清除） |
| `godot/tools/fastlane/bench_fastlane_arch.py` | 快速通道 HEAD vs 目前版本效能對照 |

```bash
B="D:/Blender/blender-5.2.1-windows-x64/blender.exe"
# 有連接表：驗證＋Scene Graph＋查詢＋修正預覽
"$B" -b asset.blend --python tools/blender/arch_check.py -- --map=x.arch.json [--out=r.json] [--cache=c.json] \
    [--graph=g.json] [--query="symbolic;unsatisfied:post>beam;dependents:beam;relation:roof,beam"] \
    [--fix-preview=f.json --carry=dependents|none] [--undeclared=warn|fail|off]
# 沒有連接表（Tripo GLB）：懸空零件＋未宣告穿插＋自身表面交錯；--split 拆「實體」島（先焊接頂點）；--scale 換成遊戲內尺寸
"$B" -b --factory-startup --python tools/blender/arch_check.py -- --glb=x.glb --scan --split --scale=3.2 [--graph=g.json]
# Blender → Godot 期望值（給快速通道 --expect 或 arch_glb_probe.gd）
"$B" -b asset.blend --python tools/blender/arch_check.py -- --godot-expect=e.json [--front-node=MARK_Front]
# 回歸
"$B" -b --factory-startup --python tools/blender/test_arch_spatial.py -- --glb-out=<dir>
godot --headless --path godot --script res://tools/test_arch_spatial_lib.gd
godot --headless --path godot --script res://tools/arch_glb_probe.gd -- --glb=<dir>/arch_axis_test.glb --expect=<dir>/arch_axis_test.expect.json
python godot/tools/fastlane/test_fastlane_arch.py        # 約 3 分鐘（5 次快速通道）
```
exit：有 FAIL → 1；只有 UNKNOWN → 3；其他 0。

## 連接表格式（`*.arch.json`）

```json
{
  "building_id": "s01_torii_a", "style": "japanese_shrine",
  "frame": {"origin": "MARK_Origin" | [x,y,z], "front": "MARK_Front" | "-Y" | "local:-Y@root"},
  "components": {"torii": {"object": "s01_torii_a" | "arch_id": "T-001", "type": "gate", "role": "structure"}},
  "constraints": [
    {"id": "torii_on_base", "type": "SUPPORT", "a": "torii", "b": "base", "embed_max": 0.03, "priority": "hard"}
  ],
  "sample_step": null, "check_detached": true
}
```
- `frame`：建築自身座標。`right = front × up`（建築面朝 front 時自己的右手）；左右／前後一律用這個，不用世界 X/Y。預設 front = Blender −Y = Godot +Z。
- 穩定識別：`arch_id` → 找自訂屬性 `arch_id` 相同的物件（改名不受影響）；否則 `object` 名。
- 構件用途 `type`／`role` 只取連接表或物件自訂屬性 `arch_type`／`arch_role`，**不從名稱猜**；沒寫的列入 graph `limits`。
- 容差：`tol`（公尺，角度為度）、`tol_rel`（× 兩構件最小尺寸，取大者）。`priority: soft` 違反時記 WARN。

| type | a / b 意義 | 量法 | 主要參數 | Graph 關係 |
|---|---|---|---|---|
| SUPPORT | a 由 b 支撐 | 封閉：雙向射線＋先判內外；非封閉：最低帶頂點上下最近面（上下等距 → UNKNOWN） | `embed_max` 0.01、`min_contact` 0.7、`require`、`contact_band` | b SUPPORTS a |
| CONTACT | 應貼合 | 雙向取樣 → `find_nearest`；相交時量穿透深度 | `tol` 0.002、`allow_depth` | CONNECTED（a 的 role 是 decor 等 → ATTACHED_TO） |
| SNAP | 模組對接 | 錨點距離；或接縫間隙分布＋面反向平行 | `anchor_a/b`、`angle_tol` 2° | CONNECTED |
| OVERLAP_ALLOWED | 榫接／屋瓦搭接 | 穿透點須在 `region` 內、深度 ≤ `max_depth`；分開則 FAIL | `region`、`max_depth`、`must_touch` | CONNECTED |
| CLEARANCE_REQUIRED | 門扇／通道淨距 | 最小距離在 [min, max] | `min`、`max` | SEPARATED_FROM |
| NO_INTERSECTION | 不得穿插 | 穿透深度（共面／擦邊不算） | `tol` 0.001 | SEPARATED_FROM |
| SYMMETRIC | a 鏡射 ≈ b（a=b 自身對稱） | 鏡射取樣 p95＋重心差 | `plane` | MIRRORS |
| PARALLEL / PERPENDICULAR | 軸向 | `acos(|a·b|)` | `axis_a/b` | ALIGNED_WITH／PERPENDICULAR_TO |
| COAXIAL | 中心線對齊 | b 中心到 a 軸線距離 | `axis`、`center` | ALIGNED_WITH |
| FACING | a 正面朝 b | a 正面軸（預設 `local:-Y`）水平投影 vs a→b | `axis_a`、`tol` 10° | FACING |
| CONTINUOUS | 有序清單（石階） | 頂高級差一致＋相鄰接縫 | `rise_max`、`gap_tol` | — |
| EVEN_SPACING | 柱列 | 間距相對偏差（預設 soft） | `axis` | — |

另外每次都跑：**DETACHED**（接觸圖從最低構件洪水填充）與**未宣告穿插**（AABB 只當候選，BVH 確認）。

## 結果欄位（Blender 與 Godot 同一份）
`rule_id, type, building_id, object_ids, status(PASS/WARN/FAIL/UNKNOWN), priority, severity, expected, actual, deviation, tolerance, method, suggestion, evidence, fix`
報告另有 `summary`、`unknown_reasons`（原因 → 數量）、`scan_stats`。`fix` 是建議的最小修正（平移／yaw），不會自動套用。

## UNKNOWN 的原因分類（第三節）
| reason | 意義 | 狀態 |
|---|---|---|
| COPLANAR_CONTACT | 相交的三角形全部共面 | 視為接觸（PASS），不是 UNKNOWN |
| SURFACE_CONTACT | 開口網格相交，但每對三角形跨過對方平面 ≤ 1 mm（只是貼合／擦邊） | 視為接觸（PASS） |
| SURFACE_CROSSING_NO_VOLUME | 開口網格表面真的交錯（記最大交錯量），但沒有封閉體積 | UNKNOWN；交錯量**不能**當穿透深度 |
| BELOW_SAMPLING_RESOLUTION | 有封閉體但取樣點沒落進去，交錯量 > 解析度 | UNKNOWN；調小 `sample_step` |
| SELF_SURFACE_CROSSING | 單一網格自身（非相鄰三角形）交錯 | UNKNOWN；分不出嵌合或穿模，看近照 |

掃描模式每種原因只出一列：數量、交錯量直方圖、最大的前 20 對（真正的問題排最前面）。

## Scene Graph 查詢（`--query`，`;` 分隔）
`symbolic`、`nodes:<type>`、`edges:<REL>`、`unsatisfied:<a_type>><b_type>`（哪根柱子沒接到梁）、`dependents:<id>`（被它支撐／附著在它上的）、`supporters:<id>`、`relation:<a>,<b>`（建築座標方向關係＋宣告／觀察到的邊）。
觀察到但沒宣告的接觸邊 `declared=false`、`status=OBSERVED`。Tripo 單網格只會是一個 `opaque` 節點，`limits` 寫明內部構件無法辨識。

## 修正預覽（Phase 10，`--fix-preview`）
每個帶 `fix` 的 FAIL：記憶體內平移目標（`--carry=dependents` 連同被支撐／附著構件）→ 重驗受影響的約束 → 還原 → 回報前後狀態與 `verdict`：
`OK`（修好且沒有新 FAIL）／`BREAKS`（產生新 FAIL → 停止連鎖，交給人）／`NOT_FIXED`。
還原後以世界網格雜湊確認 `scene_restored=true`；`written=false`，P1 不啟用正式寫入。

## 快速通道（Godot）新增
- **consistency**：GLB 原始資料（GLTFDocument）vs 匯入節點：AABB、原點、旋轉（atan2，float32 下也到 0.0001°）、每軸縮放、行列式；`--expect` 另比 Blender→GLB→匯入＋正面標記；放置後比 `FastLane/<id>/Model/…` 整條 Parent 鏈。缺節點 FAIL、多節點 WARN、讀不到頂點 UNKNOWN。
- **layout**（第 4 項）`--layout=organic|structured|landmark|off`：參考線＝`layout_v2.json` roads＋lanes 中心線；曲線用最近點 ±6 m 的局部切線。
  - 全模式：腳印侵入路面（< −0.05 m）→ FAIL。
  - organic：入口離路緣 ≤ 15 m、路不在入口背後（hard）；正面偏 ≤ 35° PASS、≤ 90° WARN、其他也只 WARN。
  - structured：入口 ≤ 6 m；正面 ≤ 10° PASS、≤ 20° WARN、其他 FAIL；`--setback`；同側鄰棟（FastLane/*、B_*、Hero）中位退縮 ± 1 m；間距 < 0.3 m WARN；鄰棟不足 2 → UNKNOWN。
  - landmark：不要求朝路（只記錄）；`--axis-target=x,z` 或 `--sando=<道路名>` 主軸 ≤ 5° 且軸線偏移 ≤ 1 m PASS，≤ 15° WARN；沒給參考 → UNKNOWN。

## 可信度邊界（實測）
- 穿透深度需要至少一方封閉網格；解析度 ≈ 取樣步距。平行面間隙是精確值。
- 快取鍵含所有相關構件的世界評估後網格雜湊：頂點、修改器、Transform、Parent 任一變動都失效。
- Blender→Godot `(x, y, z) → (x, z, −y)` 由實際 GLB 往返驗證（偏差 0.000000 m）。
- glTF 在 UV／法線接縫複製頂點：拆島必須先焊接。手水舍未焊接時是 1,815 個假島、1,813 對假 UNKNOWN；焊接後是 2 個實體零件、0 相交、自身交錯 0。
- 道路參考線是 layout 的設計中心線（凍結權威）；畫出來的路面蛇行在原路寬內，但不是逐點貼合。
