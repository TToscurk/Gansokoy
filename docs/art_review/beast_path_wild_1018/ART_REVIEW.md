# 獸道 S01–S03 荒野化：環境美術重製 — ART_REVIEW

- 日期：2026-10-18　引擎：Godot 4.7.2　狀態：**ART_REVIEW**（待使用者裁定；未 ART_APPROVED、未升凍結基準、未 commit）
- 目標：從「郊外公園／村緣」改成「危險、荒野、妖怪出沒的獸道」。S01：村緣漸入荒野；S02：幽暗茂密深林；S03：野性分岔。
- 備份：`D:/神社/_backup/beast_path_pre_wild_20261018/`（tools／maps／assets／meta，75 MB），另有 git HEAD `eda9d81` 的獸道基準。

## 前後對照（同鏡位、10:00；每組左＝前、右＝後）

- `S01_before_after.jpg`：44 組
- `S02_before_after.jpg`：15 組
- `S03_before_after.jpg`：12 組
- 數量明細：`_counts.md`（改前＝git HEAD，改後＝工作目錄）

## 改了什麼

**移除文明感**
- 撤掉農田（畝、作物、地形平台）、農舍、柴堆、籃子、田邊柵、鳥居兩側的整齊橫木柵，原 POI 收進 `_retired_pois`，可查可還原。
- 撤掉 S01 的櫻林聚落、小屋後綠籬、草坪空地 `meadow_open`、農田空地。
- S01 的 7 棵櫻（含 5 棵釘點櫻）換成同高度的野生樹：枹櫟、椎、杉、朴。
- 留下的人造物改成荒廢：
  - 鳥居朱漆褪暗（tone 0.5），台座長苔。
  - 右側石燈籠倒塌、斷成兩截，左側長滿苔。
  - 村緣與林口的柵欄歪斜、缺橫木（weathered 0.85–0.95）。
  - S01 岩石苔 ≥ 0.75。

**提高森林密度（全部是 Blender 資產或 veg_kit／bamboo_kit 的 3D 實體）**

| 區 | 樹（含釘點） | 竹 | 枯立木 | 林床（叢） | 倒木／殘株／枯枝堆 | 露根 | 岩 |
|---|---|---|---|---|---|---|---|
| S01 | 313 → **562** | 0 → **88** | 0 → 5 | 13,694 → **23,329** | 23 → 47 | 12 → 74 | 31 → 30 |
| S02 | 436 → **649** | 0 → 23 | 5 → 21 | 15,566 → **24,819** | 25 → 65 | 32 → 90 | 33 → 68 |
| S03 | 374 → **570** | 317 → 359 | 3 → 15 | 16,165 → **27,613** | 14 → 47 | 60 → 100 | 79 → 121 |

- 林床組成從草坪改成林下：
  - S01 高草／短草 5,267 → 42 叢。
  - S01 蕨 1,933 → 6,565，笹 424 → 1,612，灌木 306 → 1,133。
- 沒有碰撞的植物（蕨、笹、灌木、雜草）可以長到離路緣 0.6–1.4 m，原本是 1.6–3 m。
- 林床沿整條主路與支線鋪設：S01 原本只鋪 R4／R5 兩個矩形，改成 band 30 m＋全區 bbox。
- 加樹採高低混種，45–55 % 帶 1.5–7° 微傾。
- S02／S03 新加的樹以闊葉為主，讓樹冠蓋過路面。
- 舊農田變成竹藪 `wild_bamboo_oldfield`，原草坪改成竹叢，S02／S03 各加一叢。

**區域差異**
- S01：密度沿 z 漸增，村端（z > 0）每 100 m² 加 0.6 株，到 S02 接縫加 3.8 株。
- S02：杉＋闊葉閉冠，加林中幽暗層：霧密度 0.0012 → 0.008，亮度 ×0.88，飽和 ×0.88，相機 z −60→−112 淡入。
- S03：混林、歪斜最多，岩組最多。
- 幽暗層在 z −312→−336 淡出，接縫 −340 之前就回到原值，S04 與 BOSS 的大氣不變。

## 驗證（實際執行的結果）

| 項目 | 結果 |
|---|---|
| `verify_beast_path.gd` | 81 項中 76 PASS。5 FAIL 全部是預期內或改前就有的，見下表 |
| 主路與各支線的玩家膠囊掃描（`capsule.*`） | PASS，路線沒有被碰撞物擋住 |
| 真玩家實走 `walk_beast_path.gd` | **7 腿全部到達**：主路往返 403／402 m、竹林、巢穴環、回程小路、出口祠、BOSS 場一圈 |
| MultiMesh 烘焙回讀（MMBAKE） | S01／S02／S03 零矩陣都是 0（instance 41,475／43,445／48,201） |
| 有碰撞的岩／木離主路路緣 < 3.5 m | 3 區都是 0 件 |
| 貼地 | 岩／木走 `ground_fit`（依地面線下沉），新樹用地形高度減坡度下沉 |
| S04 保護 | `s04_*` 場景與 gen 檔相對 git HEAD 零變動。`forest.s04_v12_kept`、`meadow.s04_v12_kept`、`pool.shore_v12_kept`、`forest.zone_independent`、`sky.atmosphere` 都 PASS |
| 林床長在路面上 | S01 2 叢、S02 1 叢，都是無碰撞小草 |

5 個 FAIL：

| Gate | 原因 |
|---|---|
| `trees.match_plan` | 改前就 FAIL（forest_plan 與場景實例數本來就不一致） |
| `s01.count_budget`、`s01r2.total_kept` | R1／R2 的 S01 總量上限 380 株。本輪就是要加密，713 株是預期 |
| `s01r2.pins_moved_limited` | 5 棵釘點櫻換成野生樹，預期 |
| `isolation.s01_terrain_locked` | 拿掉農田的平整地形平台，S01 地形與碰撞重算，預期 |

沒做的驗證：依指示不做效能跑分。林床 LOD0 三角形總和約變成兩倍（S01 5.4M → 12.9M、S02 7.0M → 12.7M、S03 7.0M → 13.7M），樹 +46～+80 %。實際每幀成本受 LOD／淡出影響，**未量測**，建議下一步量一次。

## 圖像審圖（自評，不是 gate）

- **S01**：天空主導鏡頭約 85–90 % 降到約 5 %，草坪主導約 35–40 % 降到約 5 %，封閉林感約 10 % 升到約 45–70 %。農田、小屋、櫻都看不到了。
- **S02**：15 組中 11 組明顯更陰暗封閉，遠景樹林被霧吃掉。
- **S03**：12 組中 6 組明顯更野，5 組差不多，1 組（`z3_wide`）變差。

## 已知不足（請裁定）

1. **路面仍寬而整齊**（3.5–5 m 的乾淨土路）。林床植物都乘 `(1−dirt)`，長不上路面。要變窄只能改地表的路／路肩通道，或直接改路寬（主要路線），所以本輪沒動。
2. **霧色偏淺灰**：霧色由 `daynight.gd` 每 0.02 h 寫入，本輪只動了霧密度、亮度、飽和。要做暗綠或冷色的妖霧，需要改日夜系統或加一層覆寫。
3. **高處審圖鏡位埋進新樹冠**：`z2_wide`、`z3_wide`、S01 的 `d_wide`／`h_entrance`／`g_wide_back`。這些是自由鏡位，不是遊戲相機；第三人稱鏡頭有幾張樹幹或幼樹靠近鏡頭（`z2_hollow`、`z2_lung_in`、`z3_glade_in`）。
4. **鳥居仍是 S01 的視覺焦點**：形狀完整，只是褪色、長苔。若要「斷鳥居」，需要新的 Blender 破損版。
5. **效能未量測**（見上）。

## 還原開關

- `layout.forest.wild.enabled=false`：回到原規劃，沒有加樹、竹、枯木，櫻還在。
- `layout.atmosphere.gloom.enabled=false`：關掉幽暗層。
- `_retired_pois` 裡帶 `_wild_1018` 的 7 件搬回 `pois`，農田地形平台與兩個空地照 git HEAD 加回。
- 林床參數改動都寫在各 `s0x_dress.json`，還原用 git，或用上述備份的 tools 資料夾。

## 改動的檔案（工具與資料；場景與 gen 是重新生成的產物）

- `tools/beast_path/forest_planner.gd`：`_wild_pass` 及其工具函式。
- `tools/beast_path/layout_beast_path.json`：POI、空地、stand、`forest.wild`、`atmosphere.gloom`。
- `tools/beast_path/s01_dress.json`、`s02_dress.json`、`s03_dress.json`：林床參數。
- `tools/beast_path/bake_s01_dress.gd`：S01 範圍改成整區。
- `tools/beast_path/s01_arch.gd`：鳥居 `paint_tone`。
- `tools/beast_path/generate_beast_path.gd`：傳入 gloom 參數。
- `maps/beast_path/bp_atmosphere.gd`：gloom 層。
- 重新生成：`s01_entrance.tscn`、`s02_deep_forest.tscn`、`s03_crossroads.tscn`、`beast_path.tscn`、`gen/s0{1,2,3}_dress.scn`＋report、`gen/s0{1,2,3}_terrain.res`、`gen/s01_terrain_shape.res`、`gen/forest_plan.json`、`gen/s01_forest_inputs.json`。
