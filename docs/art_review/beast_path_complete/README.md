# 獸道 S01–S03 環境美術 — **ART_APPROVED**（使用者裁定 2026-10-17）；S04 另案

| 範圍 | 狀態 |
|---|---|
| **S01–S03 環境美術** | **ART_APPROVED**（使用者 2026-10-17「Beast Path Environment Art: Final Review Decision」）。不再迭代；沒有新發現、玩家看得到的重大缺陷或明確授權，不重開。 |
| S04 | V1.3 保護、凍結，本輪未改。BOSS 戰鬥攝影機整合審查**另案、未批准**。 |
| S02 森林門效能 | **驗收待定**（見 §10）。 |
| 凍結基準 | **未升級**（`frozen/` 與 `protected_v13_manifest.json` 未改）。批准的是目前工作區候選狀態，雜湊記於 `APPROVED_S01-S03_candidate.sha256`。 |

未 commit、未刪任何既有未追蹤檔或備份。指令：`pasted_content_2026-10-16_16-43-55-666_3c81ce.txt`（全區製作）→ `pasted_content_2026-10-17_03-33-07-426_b34798.txt`（最終整合）→ 裁定（批准）。每次開工前讀憲章 `.hermes.md`＋JEV CROSS_CHECK（30 題 28 符合；整合後裁定 22 題 20 符合，兩題差異 Jev 判得更嚴，照嚴格解讀）。最終整合細節：`closure/README.md`。

## 1. 代表圖與比較（同機位、10:00、1600×900、第三人稱）
- `0_S01-S04_representative.jpg`：S01 鳥居／農田 → S02 深林／橋 → S03 岔路／竹林／林窗 → S03→S04 接縫 → S04 緩衝區／BOSS 場。
- `1_S02_before_after.jpg`、`2_S03_before_after.jpg`、`3_seams_before_after.jpg`（zs_12／zs_23／zs_34／z4_buffer）、`4_S01_R6_vs_final.jpg`（R6 → 本輪）。
- 全部原圖：`before/h10/`（25）、`after/h10/`（33，含 R6 七個 S01 鏡位與 `z4_arena_fwd`）。

## 2. 做了什麼
| 區 | 內容 |
|---|---|
| S01 | R6 構圖不動（鳥居、燈籠、農田、櫻、R5 林床 13,694 叢逐叢相同）。換掉剩下的白模：柵 7 段、路標、入口小祠＋石段、石標、岩 6 組 18 顆（二十面體團塊→kit 岩）、農具小屋（盒子＋三角屋頂→板壁板葺）、薪、竹籠。北端地表淡出改成接縫收尾。 |
| S02 | 地表：白模平塗 → S01 的 13 通道森林地表（落葉、苔、濕土、路面）。林床：Blender kit 15,566 叢（蕨、笹、蕗、闊葉草本、幼樹、灌木、苔、落葉、枯枝）＋ 90 件岩／倒木／露根（24 有碰撞）；比 S01 更濕暗、蕨與倒木多。道具：石段、丸太板橋＋石積み橋台、飛び石、柵、殘株、露根、供物、岩。溪水：白模藍板 → 與 S04 同一個水 shader（新材質檔）。 |
| S03 | 與 S02 區隔：老林＝露岩、岩肋、苔石、露根多，林窗草花，竹林下＝苔／落葉／笹（竹算樹冠），蕨與幼樹少。16,165 叢＋153 件（34 碰撞）。岔路舊石鋪邊緣讓苔／短草長進來，兩個楔形地放苔岩＋倒木把開闊面收成路。道具：小祠＋基壇＋石段＋柵、道標、道標石、燈籠 ×3、倒れ燈籠（上下兩半）、木戶、小鳥居（S01 鳥居 0.68 倍、褪色）、供物、石段、飛び石、露根、岩。 |
| S04 | **未改**（V1.3）。只拍接縫與代表圖；`s04_boss_clearing.tscn` 與開工前逐位元相同（本輪沒有對 S04 執行 generate）。 |

## 3. Blender 資產（`assets/beast_path/s01_kit/src/build_bp_props.py` → `glb/`、`props_manifest.json`、`bp_props.blend`；`5_blender_props.jpg`）
26 件、固定 seed 可重現：自然石段 ×5（不規則割石）、土留丸太 ×2、丸太桁板橋（10 m，Godot 依原橋長伸縮）＋空石積み橋台、小祠（切妻板葺・格子戸・注連縄紙垂）＋切石基壇、農具小屋（4.6×3.6 m、縦板壁・板葺・押さえ木）、木戶、道標柱＋矢印板、道標石、柵杭／橫木、供物＋供石、竹籠、薪、飛び石 ×2、春日燈籠上下半（倒れ燈籠用）。既有 s01_kit（原 27 件＋R5／R6）106 檔逐位元未動。
重用：S01 kit 的岩（露頭、崖岩、岩肋、苔石）、倒木、殘株、露根、枝、全部林床植物。

## 4. 植被／地質構成
- 同一套擺放（R5 的棲地×群落×林窗），各區自己的設定：`tools/beast_path/s02_dress.json`、`s03_dress.json`（seed 52021／53031）；沿路帶 24／22 m 以內，再遠只靠地表＋樹（玩家看不到）。
- 凍結的樹逐棵原樣；V0.1 林下 prefab（kind＝under，S02 772＋S03 489＝1,261 個）在候選中不載入（`layout.forest.zone_candidate`），林床改由 Blender kit 負責。
- 地質：S02＝溪谷坡的半埋露頭與坡腳苔石；S03＝坡上露岩／岩肋＋大量苔石＋岔路楔形地岩組。**地形高度未動**。

## 5. 已知的小限制（記錄，不再磨；批准時接受）
1. ~~平地段的石段像排石~~ → 最終整合改為土留め丸太階段（`closure/`），已批准。丸太跟著碰撞箱等距、略規則＝**使用者接受的藝術瑕疵**。
2. 樹冠陰影很黑，遮掉部分林床細節（共用光照／大氣在 S04 保護範圍內，未動）。
3. 凍結的樹：遠景針葉剪影重複、樹距偏均勻（凍結檔不動）。
4. S01 谷壁大面平滑坡（依使用者先前裁定保留不完美）。
5. 岔路仍比林內開闊（規格：交會區較開闊）；小鳥居／燈籠在竹林深處遠看不顯眼。
6. S04：巨石偏方、瀑布在 BOSS 場構圖中偏小——S04 受保護，只報告不改。
7. `z2_hollow` 鏡位前景樹幹擋住角色（審圖鏡位的問題；遊戲相機有碰撞，未改）。
8. 林床 LOD 換手在 22–26 m；靜態圖看不到跳變，移動中未驗。

## 6. AABB／碰撞／場景完整性（`evidence/`）
- **玩法幾何不變**：四個場景 Props 底下全部碰撞形狀（transform＋形狀尺寸）與開工前備份逐一相同：S01 20／S02 15／S03 18／S04 53 個 POI、0 差異（`collision_cmp.txt`，`collide_cmp.py`）。換皮只換外觀。
- **接地**：換皮道具 286 個網格，懸空（最低點高於地面 >3 cm，不含附掛件）0 個（`placement_props.txt`）。林床硬物件的 AABB／離地／淨空見 `s02_dress_report.json`、`s03_dress_report.json`（離主路路緣 ≥3.5 m 才放）。
- **目標驗證**（`verify_zone.json`，headless 真物理）：25 項 23 PASS——場景載入、POI／功能標記節點、S01|S02|S03|S04 接縫列 0 差、主路與四條支線無洞、高差 ≤0.18 m、縱坡 10.1°／13.3°、玩家膠囊沿主路與支線 0 阻擋（木戶／出口封印照設計擋住）、BOSS 場中央淨空與繞行、樹接地、凍結檔雜湊與規劃逐筆相同。
  **2 項 FAIL＝預期的候選差異**：`trees.match_plan`（規劃 3,602 筆＝場景 2,341）與 `forest.frozen_scene_equal`（1,261 棵）——正好是不載入的 1,261 個 V0.1 林下 prefab，其餘每棵 transform 差 0.000000。凍結檔與檢查都沒改。
- MultiMesh：S02／S03 林床非 headless 烘焙，存後回讀零矩陣 0（`logs/bake*.log`）。

## 7. 效能（`evidence/perf_final.json`、`logs/perf3.log`；GTX 1070、1600×900、垂直同步關、每點 3 次中位數）
| 位置 | FPS | GPU ms | 面數 |
|---|---|---|---|
| S01 出生 | 70.5 | 13.8 | 5.16M |
| S01 鳥居 | 71.9 | 13.4 | 5.10M |
| S02 森林門（S01/S02 接縫） | **58.5** | 16.6 | 6.72M |
| S02 林道 | 62.6 | 15.5 | 5.81M |
| S02 橋 | 66.3 | 14.6 | 5.16M |
| S03 岔路 | 73.1 | 13.2 | 5.44M |
| S03 北段 | 70.5 | 13.7 | 4.62M |
| S04 緩衝 | 120.2 | 7.9 | 1.68M |
| S04 BOSS 場中央 | 123.8 | 7.6 | 1.63M |
S02 林床初版讓森林門掉到 47.9 FPS（林床約 8 ms）；縮 LOD 換手／淡出距離（20 m 內不變）、落葉與蕨間距、沿路帶 30→24 m、灌木不投影 → 58.5。森林門仍略低於 60（同時看到 S01 R5 南段林床），列為已知。

## 8. 保護區比較（`evidence/protected_cmp.txt`）
- `frozen/protected_v13_manifest.json`（未修改）raw 279 檔：不同 2＝`gen/s02_terrain.res`、`gen/s03_terrain.res`（只有頂點通道／材質，預期候選差異）；**`s02_terrain_shape.res`／`s03_terrain_shape.res` 逐位元相同＝地形高度沒動**；S04 全部資源、共用 shader／材質、meta、凍結檔 0 差。scene_norm：S04 raw 相同；S02／S03／彙總場景不同＝預期。`s01_locked` 相同。

## 9. 修改檔與備份
- 修改（9 程式＋設定）：`tools/beast_path/{bake_s01_dress.gd, generate_beast_path.gd, layout_beast_path.json, prop_builder.gd, s01_dress.gd, s01_floor.gd, s01_ground.gd, s01_wall.gd, terrain_generator.gd}`；生成物：`maps/beast_path/{beast_path, s01_entrance, s02_deep_forest, s03_crossroads}.tscn`、`gen/s02_terrain.res`、`gen/s03_terrain.res`、`materials/bp_ground_s01.tres`（S01 接縫參數）。
- 新增：`tools/beast_path/{zone_ground.gd, zone_props.gd, s02_dress.json, s03_dress.json, bp_zone_shots.gd}`、`maps/beast_path/gen/s0{2,3}_dress.{scn,_report.json}`、`materials/bp_ground_zone.tres`、`materials/bp_water_stream_zone.tres`、`s01_kit/src/{build_bp_props.py, bp_props.blend, props_manifest.json}`（＋Blender 自動的 `bp_props.blend1`）、`s01_kit/glb/` 26 件。
- 最終整合追加：修改 `tools/beast_path/{zone_props.gd（石段→土留め丸太階段）, s02_dress.json（遠處 LOD）, bp_zone_shots.gd（+z2_steps_on／z3_steps_on）}`、`s01_kit/src/build_bp_props.py`；新增 `s01_kit/glb/bp_step_log_{c,d}.glb`；重生 `s02_deep_forest.tscn`、`s03_crossroads.tscn`、`beast_path.tscn`、`gen/s02_dress.scn`。
- 開關（還原用）：`layout.zone_ground.enabled`、`layout.forest.zone_candidate.enabled`、`s0x_dress.json enabled`、POI `"skin": true`、`s01_ground.seam_off`。
- 備份：`%LOCALAPPDATA%/hermes/backups/beast_path_r6_20261017/`（開工前 553 檔＋R6 審圖包，sha256）；R5／R4／R3／R2 與 V1.3 備份保留。還原規則同 `RESTORE.md`（逐檔複製，不整資料夾覆蓋）。

## 10. 技術待辦（不是重開美術的理由）
1. **竹林支線台階碰撞**：上下台階瞬間腳與可見地表最多分離 26 cm，上坡 3 幀猶豫（`closure/walk/walk_steps.json`）。原碰撞為直角台階；留給之後的玩家移動／碰撞整合輪。
2. **S02 森林門效能——驗收待定**：最後一次乾淨量測 58.5 FPS（`evidence/perf_final.json`）。最終整合後 52.0 FPS 是在 GPU 被其他程式（開著的 Godot 編輯器）佔用時量的，不可比；62–64 FPS 是以未改動點換算的**推估、未實測**（`closure/perf_closure.json`）。需在無 GPU 爭用時重量一次。

## 11. 目前候選基準與還原
- **已批准候選**＝目前工作區 `godot/{tools,maps,assets}/beast_path`（573 檔，`APPROVED_S01-S03_candidate.sha256`；不含 `.import`／`.blend1`）。未進 Git、未升凍結基準。日後要升基準需另外授權並實作提升工具。
- **還原到開工前（R6）**：關掉 §9 的開關後重生 S01–S03；或從 `%LOCALAPPDATA%/hermes/backups/beast_path_r6_20261017/repo/` 逐檔複製（先確認目標檔沒被別的 session 改過，不整資料夾覆蓋、不 git clean／stash）。
- 更早備份：`beast_path_s01_r5／r4demo／r3／r2／r1_20261016`、`beast_path_v13_20261015`、`beast_path_v13_1_water_20261015`、`beast_path_v12_20261015`，全部保留。

## 12. 既有驗證限制
- 目標驗證 25 項中 2 項 FAIL＝預期候選差異（V0.1 林下 prefab 1,261 個不載入）；凍結檔與檢查未改、未放寬。
- 未跑完整歷史驗證矩陣；S04 的 V1.2／V1.3 美術 gate 本輪未重跑（S04 未改，雜湊相同）。
- 實走只涵蓋 S02／S03 的四組階段（4 腿）；其餘路段用膠囊掃描（headless 物理）而非真玩家輸入。
- 林床 LOD 換手只在靜態圖檢查，移動中的跳變未專門驗。
- 效能只有一組乾淨量測（58.5 FPS 版），最終整合後無乾淨量測。

