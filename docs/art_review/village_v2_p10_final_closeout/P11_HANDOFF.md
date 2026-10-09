# P11 — Collision & Navigation HANDOFF（自 P10 FINAL CLOSEOUT，2026-10-10）

使用者 P10 FINAL CLOSEOUT 指定的 P11 優先順序：
1. 真實玩家實走
2. NPC 路線
3. 建築門前障礙
4. 神社相機碰撞
5. 場景傳送落點
6. 導航連續性

本檔只列出 P10 確認過、並移交給 P11 的事項與證據。這些都**還沒有修**。P11 開工時仍以 `.hermes.md` 與總計畫為準。

## 0. 前提（P11 不得破壞的封存）
**已封存**：
- P7、P8：P8 已在 2026-10-10 依 R5b.1 limited reseal。
- P9 FINAL。
- P10 R1／R1b／R2／R3b–R3e／R4／R4b。
- P10 R5c／R5a／R6a／R4c。

**修改封存的規則**：
- 只能 limited correction，並保留前後雜湊、`reseal_history` 與反向測試。
- 不能放寬舊 Gate。
- 人口 51 人的身分、位置、動作，除非是真正的碰撞或導航 bug，否則不改。

**其他 session**：
- `scripts/main.gd` 是另一個 session 的 HOLD。
- 玩家相機（`characters/yoriichi/*`）屬於 Yoriichi 相機 session。

## 1. 建築門前障礙
| # | 位置 | 現象（實測） | 證據 | 備註 |
|---|---|---|---|---|
| 1-1 | **B_P_MKT_003** 店前（同型：B_P_MKT_008） | P10 R2 StreetP10 的店前台 **0.52 m**，玩家在 Kit Gate 的 F5 實走時被抬起，**離地最大 0.43 m**。Kit Asset Gate render 項 `f5_f6` 因此 FAIL。 | `docs/art_review/village_v2_p10_rehab_impl/integration/r6a/manifest_route_attempt/` | 使用者裁定 TRANSFER TO P11。**Kit manifest／`gate.json`／asset registry 維持現狀**，不為此改寫 Kit 驗證結果。平時的回歸不跑 render 項，所以這是既有、但先前沒被抓到的跨層衝突（P6 Kit × P10 R2）。 |
| 1-2 | 全村 187 棟入口 | 1-1 是 Kit Gate 只抽 8 棟代表實走時發現的，其餘入口沒有實走。 | — | 建議 P11 用 StreetP10 的店前台／縁台清單，對全部入口做 1.7 m 膠囊實走。 |

## 2. 神社參道（碰撞／平台／NPC／相機）——外觀延到 P13
- **現況**：
  - `ShrineApproachP10`（r8：石段 186、踊り場 3、斜坡碰撞＋盛土踊り場碰撞）**未 ART_APPROVED，也未封存**。
  - r8 與 R6b.1 新石段 Kit Pilot（只在記憶體生成，場景沒動）都保留作比較候選。
- **P9 R4-2 場景級 gate 衝突（Newly Introduced，從 ROUND 2 起）**：
  - 盛土踊り場的斜坡碰撞，命中封存 gate 的地形基準膠囊 40／179 點。
  - 把 ShrineApproachP10 移除就 PASS。
  - 舊 gate 沒改。
  - SWALK（`tools/verify_village_v2_sando_walkable.gd`）是「可行走面／scope-aware verifier correction」**提案**，已通過，但**不能拿它更改 P9 R4-2 的封存判定**。P11 定下參道碰撞後，才做 P9 R4-2 limited verifier correction／reseal。
- **NPC**：ROUND 2 已確認巡回干涉 0。P11 需在最終碰撞形狀上重測。
- **相機**：已交接給 Yoriichi 相機 session（`docs/art_review/village_v2_p10_rehab_impl/r6b1_shrine/CAMERA_HANDOFF_yoriichi.md`）。
  - 下行拉近數據：pitch −0.18 時 55 %、5 次；−0.35 時 5 %、1 次。
  - 只有地形時也有 73 %。
  - 根因是 30° 坡對應 −0.18 的 pitch，不是碰撞形狀。
  - **不得用關閉相機碰撞來處理。**
- **其他相機問題**：
  - C1 參道鳥居腳 (289.5, −167.7)：轉身下參道時，SpringArm 4.4 m 會進入山坡地形約 0.9 s（`docs/art_review/village_v2_p10_final/review/camera_check.jpg`）。
  - 頂端社殿前起步點的拉近 1.5 m 與坡度無關，要另外檢查社殿前的碰撞形狀。

## 3. 場景傳送落點
- **R5c-02**（MASTER AUDIT）：`scripts/main.gd _place_player()` 找不到 `target == "village_v2"` 的 portal 時，用 `(0, 40, 0)` 讓玩家自由落下。
  - 實測從 V2 去 trail／hieda1f／kourindou，會落下 1.85 s，落在 y 3.1–4.2，室內圖疑似落在屋頂上。
  - 建議 A：先用 alias（`village_v2`↔`slice`↔`village`）重找，找不到再用 `meta.spawn` 或第一個 portal，**永不用 (0,40,0)**。
  - Gate：落點離 portal ≤ 6 m、0.5 s 內著地、墜落高差 ≤ 3 m。
  - **`main.gd` 由另一個 session 持有，必須先協調**（使用者 D1 HOLD）。
  - 證據：`docs/art_review/village_v2_p10_rehab_audit/MASTER_AUDIT.md` R5c-02。
- 正式流程仍載入 `slice`，不是 V2（總計畫 §52 刻意如此）。P11 要釐清落點測試應該以哪張圖為準。

## 4. NPC 路線
- **B1 主街南段無人流**（P10 FINAL walkthrough 提案 BLOCKER，**使用者尚未裁定**）：
  - 範圍是南大鳥居 (234, 100) 到中橫街 (262, −20)，約 125 m，沒有 NPC。
  - 最小修正方案：R3d limited reopen，移動 3–4 人或延長既有巡回，總數 51 不變。
  - 屬於人口，不是碰撞，但會影響「導航連續性／玩家主路線」的觀感。
- **P9 R4-3 寺子屋 scene gate**（Pre-existing）：R3d 的 C20 巡回 NPC 擋住封存 gate 的檢查射線（跨層）。
  - 建議修正驗證器 scope（不放寬判準），**待使用者同意**。

## 5. 其他相機／碰撞
- **Market West SpringArm 穿屋頂**：獨立的 tech debt（P10 R1b 記錄），跟 2 的相機問題同一類。
- **竜骨車**（R5b.1，P8，2026-10-10）：
  - 碰撞組成：柱 8、`RyuHead`（拐木旋轉區＋0.2 m）、`RyuRail`、`RyuTrough`、`Feed`。
  - FEEDER 的實走、起跳、相機 1620 姿勢都已 PASS。
  - 送り樋的碰撞頂離地約 0.54–0.61 m，接近 `step_height` 0.6，玩家**可能踩上去**。P11 實走確認是否要擋。
- **R5a 道路**：RoadBaseP10 只換可見網格與地形 `COLOR.r`，碰撞沒變。P11 實走時，若可見路面和碰撞地形有明顯段差，要回報（目前未量測）。

## 6. 導航連續性
- 目前**沒有**全村 NavigationMesh：`village_v2.tscn`、`tools/*village_v2*`、`maps/village_v2/scripts_p10`、`characters/npc` 中，`NavigationRegion3D`／`NavigationAgent3D`／`NavigationMesh` 的 grep 結果都是 0。NPC 都是封存的 Idle／短巡回，沒有用 navmesh。
- P11 若要建 navmesh：
  - 封存的 overlay 碰撞（P8 田埂、P9 地被不含碰撞、P10 店前台、參道斜坡、竜骨車）都要納入。
  - 不得以改封存碰撞的方式讓 navmesh 通過。

## 7. 帶入後續階段的技術債（明列；不屬 P11 也列出）
| 項目 | 現況 | 歸屬 |
|---|---|---|
| P5 asset reset 白名單違規 421 | 清單與 ROUND 2 相同；R6a 不再 +19 | 既有、不擴白名單 |
| terrain gate 場景載入 3.5–4.3 s（> 3 s） | headless 參考值 | P12 |
| P9 R4-3 寺子屋 scene gate | 被 R3d C20 巡回擋住 | 驗證器 scope 修正待同意 |
| P9 R4-2 參道 scene gate | ShrineApproachP10 盛土踊り場 | P11 碰撞定案 → P13 外觀 |
| 水車 1／3 的 zone 取水 | 仍以「水車揚水到高架樋」為前提 | 使用者：暫不修改 |
| R6b 石段外觀 | r8／R6b.1 Pilot 皆 3/5 | P13 |
| 竜骨車可讀性 | 2–4/5（柳陰、水車重疊、無操作者） | P13 |
