# P10 R5–R6 — 已核准 4 工作包 正式整合＋封存報告（2026-10-09）

依使用者 ROUND 3 FINAL ART DIRECTION：R5c Boundary Closure、R5a Road Base 416 m Pilot、R6a Kit Material 24 Buildings Pilot、R4c Straw Geometry Pilot＝ART_APPROVED（**只限 Pilot 範圍，不代表全村套用**）。R5b 灌溉與 R6b 石階外觀未核准 → **未封存**，另見 `../r5b1_irrigation/R5B1_IRRIGATION_DESIGN_REVIEW.md`、`../r6b1_shrine/R6B1_SHRINE_APPROACH_DESIGN_REVIEW.md`。

## 1. 新封存（seal writer `tools/seal_p10_rehab.py`；驗證＝各 gate `--seal`，含記憶體竄改反向；封存中 `--build／--attach` 一律拒絕）
| 封存 | 對象 | frozen／evidence／images | 固有 live 檢查 | 回歸 tag |
|---|---|---|---|---|
| `data/village_v2_p10r5c_seal.json` | EdgeClosureP10（HumanUseExpansionP10 之後） | 6／8／45 | 林帶・遠景描画あり（數量＝overlay 雜湊凍結，不增林帶） | EDGE |
| `data/village_v2_p10r5a_seal.json` | RoadBaseP10（PropFixP10 之後）＋依存 GroundPilotP10 | 17／20／29 | **再現性**：生成器在記憶體重生成的道 3 本＋地形與封存 overlay 的 mesh 陣列完全一致；地形 COLOR.r 修正＝577 頂點；元の road_*.res／terrain_farmlandterrain.res 的 sha 凍結 | RDB |
| `data/village_v2_p10r6a_seal.json` | AlbedoPilotP10（EdgeClosureP10 之後）＋Kit 專用校正材質 | 30／35／37 | 材質全部是登記變體、Pilot 24 棟、適用面 > 0 | ALB |
| `data/village_v2_p10r4c_seal.json` | PropFixP10（ShrineApproachP10 之後） | 12／7／18 | st_hasa→st_hasa_v2 18 個、A2 籠移位 1 件＝R4 snapshot | R4C |

## 2. 各工作包的正式整合
### R5a（577 頂點權重修正納入可重現的正式生成流程）
- 正式流程＝`gen_village_v2.gd`（P1–P7，未改）→ 依序掛載封存 overlay（… → PropFixP10 → **RoadBaseP10**）。RoadBaseP10 的生成器以元の road_*.res／terrain_farmlandterrain.res（sha 凍結）為輸入，決定性地重生成道 3 本＋地形（只改 COLOR.r 577 頂點），runtime 替換；`--seal` 每次在記憶體重算並與封存 overlay 逐陣列比對（頂點・法線・UV・UV2・索引・顏色）。
- 若日後重跑 gen 使元の res 改變 → RDB seal FAIL → 需重新驗證／封存 RoadBase（不會無聲失效）。
- P7 地形檔 `terrain_farmlandterrain.res` 本身**未覆寫**（sha 7f5c3a9f… 不變）。
### R6a（使用已登記的 Kit 專用材質，保留防任意 override 的 Gate 能力）
- 材質移到 `maps/village_v2/kit_cal_p10/`（校正 4＋調色盤 14＋shader＋登記表 `kit_material_variants.json`）。值＝第一輪核准值；**與第一輪核准 r5（d84b666 內嵌材質）逐屬性比對差 0、targets／變體指派完全相同**（`r6a/equivalence_round1_r5_vs_integrated.log`）。
- **P6 Kit Gate「4 材質」合法更新**（`verify_village_v2_machiya_kit_gate.gd`）：override 只在「登記變體＋登記 Pilot 建物＋基底＝該面原材質＋登記表與變體 sha＝本封存 frozen 值」時合法；material_override、未登記、Pilot 外、基底不同、sha 不符 → 照舊 FAIL。新增永久反向 3（Pilot 外／基底不同／sha 不符）＋原有任意 override 反向，全部進回歸（`runneg`，必須 FAIL）。
- **不是放寬**：原本「無 override」→ 現在「只允許封存登記的 18 個變體、只在 24 棟」。KIT 回歸 ✓。
- P5 白名單：ROUND 3 Pilot 的 `assets/village_v2/machiya_kit_cal/`（未登記資產目錄）造成 +19 → 移到 `maps/village_v2/kit_cal_p10/`（village_v2 overlay 生成物的許可前綴，與 R4c 的 `gen/r4c/` 同一規則）→ P5 違規回到 421，且違規清單與 ROUND 2 完全相同（新引入 0）。
- **曾嘗試、未採用的路線**：把材質放進 `machiya_kit/cal/` 並登記進 Kit manifest。manifest 一改，Kit Asset Gate 11 項須重跑；其 render 項 f5_f6 FAIL——原因是 P10 R2 StreetP10 在 B_P_MKT_003 店前放的 0.52 m 台（玩家踏上去，離地 0.43 m），與 Kit 無關的跨層衝突（`r6a/manifest_route_attempt/`）。若照此寫入，registry 會把 machiya_kit 剔除 → 已還原 manifest／gate.json／prefab（sha 與整合前相同），改用上述路線。**此跨層衝突（P6 Kit render gate × P10 R2 StreetP10）原本就存在、只是回歸不重跑 render 項所以沒被發現**——待裁定。
### R4c（稻架模型＋必要的 A2 位置，只 reseal 實際受影響的依賴）
- PropFixP10 照舊在 runtime 換 st_hasa→st_hasa_v2（StreetP10／HumanUseP10／HumanUseExpansionP10 共 18 個）並移 A2 籠 1 件；street_kit、R2／R4／R4b 的 baked overlay 都不改。
- 實際受影響＝R4（snapshot 的 A2 位置、HUSE scene 的「mesh 是 kit .res」判定）與 R4b（R4 封存是其子封存）。R2 StreetP10 的封存 gate 不受影響（STR ✓）→ 不動 R2。
### R5c
- 只封存（林帶數量／遠景不變；overlay 雜湊凍結）。

## 3. Limited reseal（前後雜湊・原因・依存・反向）
| 檔 | 之前 | 之後 | 原因 |
|---|---|---|---|
| `data/village_v2_p10r4_snapshot.json` | 971e2dd8… | 3e788d0d… | A2 籠 [347.65, 0.145, −3.3] → [348.65, 0.144, −3.3]；其餘 49 件與 who／why／yaw 不變（逐件比對） |
| `tools/verify_village_v2_human_use.gd` | f22f3aa3… | 94441822… | HUSE scene「個別ノード」：PropFixP10 swaps 登記的 st_hasa_v2（＋_l1）合法；新增反向（kit 外 BoxMesh → 檢出） |
| `data/village_v2_p10r4_seal.json` | 0c428cfd… | d2dd2678… | 上兩檔 frozen 更新、子封存加 p10r4c、證據加 `integration/r4_reseal/*`；`reseal_history` kind `R4C_STRAW_GEOMETRY_A2` |
| `data/village_v2_p10r4b_seal.json` | 00a83117… | f0cd1d54… | 子封存 R4 的雜湊更新、證據加 `integration/r4b_reseal/*`；`reseal_history` kind `R4C_CHILD_R4_UPDATE`（R4b 的 40 件不變） |
| `maps/village_v2/gen/albedo_pilot_p10.scn` | 58765d63… | d77c13b2… | 材質改成外部參照 `kit_cal_p10/`（值不變） |
| `tools/verify_village_v2_machiya_kit_gate.gd` | d900995d… | 61f8be4d… | 「4 材質」合法變體機制＋3 個反向 |
| `assets/village_v2/machiya_kit/machiya_kit_manifest.json`／`gate.json`／`data/village_v2_asset_registry.json` | — | **不變**（4423bc9d…／a4ccbbc7…／e4a6098d…） | manifest 路線已還原 |
保留不動：人口 51、NPC 身分／位置／動畫、P8／P9 無關內容、R4 原 50 件（除 A2 1 件位置）、R4b A/B 40 件、R4b 被拒的 C。

## 4. 回歸（`integration/regression/full_regression.log`，140 項＝132＋封存 4＋Kit 反向 4，約 88 分）
**135 PASS／5 FAIL**（未修改任何舊 gate 讓失敗消失）：
| 項目 | 分類 | 說明 |
|---|---|---|
| terrain gate | Pre-existing | base 載入 3654 ms ＞ 3000（P12） |
| P5 asset reset gate | Pre-existing | 違規 421，清單與 ROUND 2 相同（ROUND 3 的 +19 已消除） |
| P8 取水水路淨空 FEEDER | Expected Pilot Seal Conflict（R5b 未核准） | WaterLifeP10 隱藏的高架支柱；正式修法見 R5B1 設計審查 §4 |
| P9 R4-2 神社周邊場景級 | Newly Introduced（ROUND 2 起；R6b 未核准） | 封存 gate 地形基準膠囊 40／179；SWALK（最上面可行走面）被擋 0；P9 R4-2 封存判定不改 |
| P9 R4-3 寺子屋周邊場景級 | Pre-existing | R3d C20 巡回（跨層） |
ROUND 3 的 6 個 Expected Pilot Seal Conflict 中，KIT／HUSE×2／HUX×2 已經由合法更新＋limited reseal 變成 ✓；只剩 FEEDER（R5b）。P8 runtime budget 本次 ✓（不穩定項目，不視為改善）。
最後一次 `--seal` 6 項（EDGE／RDB／ALB／R4C／HUSE／HUX）在 seal writer 最終執行後重跑 0 失敗（`integration/regression/final_seal_*.log`）。

## 5. 待裁定
1. P6 Kit render gate（f5_f6）× P10 R2 StreetP10 店前台的跨層衝突（§2 R6a）。
2. R5b.1：採用 B（竜骨車／踏車）與 P8 limited correction 授權。
3. R6b.1：Pilot 3/5，見設計審查的選項。
