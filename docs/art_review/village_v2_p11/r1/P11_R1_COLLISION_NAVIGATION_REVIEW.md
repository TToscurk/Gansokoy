# P11 R1 — COLLISION & NAVIGATION REVIEW（2026-10-10；送審，等待驗收）

本輪處理使用者「P11 — Collision & Navigation」Step 0–5。原則：
- 先確認真正原因，再做最小修正。
- 不降低 Gate 判準、不停用碰撞、不刪 NPC。
- 不改 Yoriichi 相機、角色控制器、main.gd。
- 封存內容只做 limited correction，並保留前後 hash、依賴與反向測試。
- 不開新的 P10 美術工作包，不提前進入 P12／P13。

## 0. Baseline & Ownership
- **工作環境**：`D:/神社/shrine`，分支 `yoriichi-combat-and-village-routing`，HEAD `de5a593`（P10 FINAL CLOSEOUT），沒有 push。使用者 staged 53 項不動。
- **其他 session 持有的檔案**（工作樹有未提交變更，本 session 一律沒碰）：
  - `characters/yoriichi/yoriichi_character.gd`
  - `player_yoriichi.tscn`
  - `scripts/main.gd`
  - `scenes/main.tscn`
  - 另有 `data/dialogue/*`、`mapRegistry.json`、`quests/mq09.tres`、`slice.meta.json`
- **相機**：`player_camera_adapter.gd` 最後修改日期 09-07，工作樹沒有變更 → 相機 session 尚未完成 pitch 修改。
- **讀過的文件**：`P11_HANDOFF.md`、`P10_FINAL_CLOSEOUT.md`，以及現有 Collision／Navigation 驗證：
  - SHRINE／SCHOOL scene gate
  - Kit Gate f5_f6
  - FEEDER／ZONE
  - `audit_village_v2_rehab_runtime.gd`
  - `walk_p10_final.gd`

## 1. 三項已知問題

### 1-1 P9 R4-2 神社參道 40 個阻擋點 → **已修正**（limited verifier correction）
**真因**（`diag/known3.json`）：
- 封存 gate 用的膠囊，基準高度固定在地形高度 S.h。
- 但 P10 R6b 參道的斜坡碰撞 `RampCollision` 是比地形高 **0.51–0.94 m** 的歩行面。
- 所以膠囊被判成「埋進斜坡」。改以歩行面為基準後，被擋 **0**；相鄰 0.5 m 取樣點之間的段差超過 0.6 m 的也是 **0**。

**玩家實走**（`walk_r1/`）：上參道 69 m、下參道 90 m，BLOCKED／STUCK 都是 0。

**修正**（`verify_village_v2_shrine_grove.gd`）：
- 膠囊基準高度改為「歩行面」：向下射線最先打到的地形，或登記過的歩行面。登記歩行面只有 `ShrineApproachP10/RampCollision` 一個。
- 未登記的物體仍然算障礙。膠囊尺寸、路線、取樣間距都不變。
- **新增一項更嚴的檢查**：相鄰取樣點的歩行面段差必須 ≤ 0.45 m。
- 結果 179 點中被擋 0、段差違規 0。歩行面來源：地形 66 點、登記歩行面 113 點。

**永久反向**（`--scene-negatives`，已併入回歸）：

| 案例 | 結果 |
|---|---|
| N1 參道上放一個箱子 | 被擋 3 → FAIL ✓ |
| N2 斜坡碰撞整體抬高 0.8 m | 被擋 5、段差 4 → FAIL ✓ |
| N3 放一塊未登記的台 | 被擋 5 → FAIL ✓ |

### 1-2 P9 R4-3 寺子屋巡邏 NPC 阻擋 → **已修正**（limited verifier correction；NPC 與巡邏路線都沒動）
**真因**（`diag/known3.json`、`diag/npc.json`）：
- C20（小僧）在 (202.0, 20.4) 與 (206.4, 25.6) 之間來回巡邏，路線在 **(205.2, 24.2)** 橫越寺子屋入口路線一次。
- 場景剛載入時，C20 的巡邏起點（start_u 0.69）正好落在這個橫越點，所以靜態 gate 的 2 個點被 C20 擋住。
- 排除 NPC 後被擋 0。巡邏兩端（會停下來等）離路線 1.35 m。橫越點的靜態通行寬度 **6.70 m**。

**玩家實走**：入口路線來回 3 趟，NPC_CONTACT 0、BLOCKED 0。

**修正**（`verify_village_v2_school_yard.gd`）：
- Population 的 NPC 是會移動的物體，不再算進靜態阻擋。
- 改為**新增三條 NPC 動態規則**：
  - ① 停留點（idle NPC 的位置、巡邏兩端）離路線 ≥ 0.3＋NPC 半徑＋0.3。
  - ② 巡邏路線在路線帶內行走的長度 ≤ 1.5 m（只允許橫越，不允許沿路線走）。
  - ③ 橫越點的靜態通行寬度 ≥ 2×(0.3＋NPC 半徑)＋0.3。
- 靜態障礙照舊：只要 1 個點被擋就 FAIL。
- 結果：145 點被擋 0；51 名 NPC 的三條規則全部 0 違規；橫越 1 處，寬 6.70 m。

**永久反向**（已併入回歸）：

| 案例 | 結果 |
|---|---|
| N1 路線上放靜態箱子 | FAIL ✓ |
| N2 讓 C20 改為 idle 並停在橫越點 | FAIL ✓ |
| N3 巡邏一端移到路線上 | FAIL ✓ |
| N4 巡邏改成沿路線走 4 m | FAIL ✓ |

### 1-3 B_P_MKT_003 店前台子抬升 0.43 m → **真因已確認；修正需要控制器負責 session（已提案、未修改）**
**真因**：
- 台子是 P10 R2 StreetP10 的長凳 `046_sk_bench`，碰撞頂離地 0.51 m，貼著店面。
- 玩家控制器 `step_height` 是 0.6 m，`_try_step_up` 會在玩家走路撞上去時把人抬上去。
- 而且這個抬升會**連續疊加**：只把 step 降到 0.40–0.45，直線走過去仍會爬上 0.51 m；降到 0.35 時直線不爬，但沿凳緣側移還是爬得上去。
- 全村落在「會被爬上去」高度區間（離地 0.25–0.60 m）的構件碰撞有 **187 件**，其中 25 件在店前或門前。所以這是控制器層級的一類問題，不是這一張長凳的問題（`diag/steppable.json`）。

**實測**（`diag/step_*.json`、`walk_step035/`）：
- step 0.35 時，參道、踏石、門、橋、田埂、河岸石段全部可通行。
- P8 ZONE 25 段與 FEEDER 都是 0 失敗。

**提案**（`OWNER_PROPOSALS.md` A）：
- `step_height` 改成 0.35。
- `_try_step_up` 只在站在平面上時才觸發，並以 step 前的地面高度為基準限制上升量，防止連續疊加。

**未做的事**：
- 沒有改 Kit manifest、Kit Gate 或 StreetP10（依 P10 FINAL CLOSEOUT 的裁定）。
- 資料側的替代方案（把不該被踩的構件碰撞加高）需要使用者授權。

## 2. Village Walkthrough（正式 main.tscn F5 路徑、實際輸入、TPS 相機 pitch −0.18、10:00）
**路線**：`tools/walk_p11_route.json`，工具 `tools/walk_p10_final.gd`。P11 新增：
- `--start=trail`：從獸道正式落點出發。
- `tp`、`xbridge` 區間測試。
- LIFT 與 NPC_CONTACT 事件記錄。
- `--step` 診斷參數。

**連續行走 1,104 m**（s0–s9，不瞬移）：獸道入口 → 入口道路 → 南大鳥居 → 主街 → 市集 → 市集西 → 住宅後巷 → Bridge_03 → 農田 → 水車 → 參道上下。

**區間測試 2,234 m**：
- 主要橋 5 座來回。
- 建物入口：B_P_MKT_003 店前、鈴奈庵、稗田邸大宅門、寺子屋入口 3 趟、鯢吞亭、霧雨店。
- 窄巷：市集西路地 1／2、主口路地、住宅後巷。
- 森林邊緣。

| 項目 | 結果 |
|---|---|
| 獸道落點 | (220.8, 0.18, 169.6)，離 portal 4 m，從 1.18 m 落下、0.32 s 著地 |
| 卡住（BLOCKED／TIMEOUT） | 連續段 **0**。區間測試有 3 次（鈴奈庵、鯢吞亭、霧雨店），都是故意往建物正面走、停在 Hero 牆前 0.31 m。這是預期結果：沒有門可以進，也沒有穿牆或抬升（`diag/walk_r1_events.json`） |
| STUCK | 22 次。其中 20 次是上面那 3 次刻意撞牆；路地 2（寬 1.3 m）和森林邊緣各 1 次，側移後都到達目標 |
| 穿模／浮空 | 0（沒有穿進建物；著地正常） |
| 異常抬升（LIFT） | 2 次：市集西縁台 0.49 m、HumanUse 板凳 0.37 m。同屬 1-3 那一類 |
| NPC 阻擋（NPC_CONTACT） | **0** |
| 相機 ARM_PULL | 18 次：下參道 4 次，其餘 14 次是市集、路地、寺子屋前等窄處碰到建物或構件 |
| 橋 5 座 | 全部來回，0 事件 |
| fps | 中位數 45–60；最低：獸道入口 30、下參道 36 |

**邊界**（`portals/runtime_boundary_portals.json`）：15 個邊界與角落測點，玩家全速衝刺加連跳 3.5 s，**15/15 PASS**，沒有一個點越出地圖範圍或掉落。

**傳送與返回**：
- 從其他地圖（trail／hieda1f／kourindou）回到 V2：落在 V2 對應 portal 旁 4.0 m，從 1.18 m 落下、0.30 s 著地 → **可安全返回**。
- 從 V2 去其他地圖：仍落在 `(0, 40, 0)` 再自由落下 1.85 s（main.gd 的問題，即 R5c-02）→ 提案見 `OWNER_PROPOSALS.md` C。

**證據**：
- `walk_r1/walk_log.json`、`walk.log`
- `review/s0_trail_gate.mp4`／`_sheet.jpg`、`review/s9_sando_down.mp4`／`_sheet.jpg`、`review/P01–P03*.jpg`
- `walk_step035/`（step 0.35 對照）

## 3. Navigation（51 名 NPC；`diag/npc.json`）
- **巡邏 6 名**：沿巡邏路線每 0.1 m 取樣，NPC 碰撞與靜態碰撞的穿插 **0**。
- **idle 45 名**：其中 3 名（W4、C22、O7，都是 yakusou_f01）坐在 Activity 座位上，與座位碰撞重疊 0.245 m。這是 R3c 封存的 Sit 動作，屬於刻意的重疊（坐著），不需修正。
- **離玩家路線 1.2 m 以內的 NPC 有 5 名**：從 NPC 旁邊繞過的最窄寬度是 1.83 m（C10），都能錯身通過。
- **人口、位置、巡邏、密度、NPC 美術全部沒動**。村裡沒有 navmesh（NPC 不用 navmesh），本輪也沒有建立。

## 4. Camera Handoff
相機 session 尚未完成修改（`player_camera_adapter.gd` 沒有變更）。本輪只提交整合需求與重現步驟（`OWNER_PROPOSALS.md` B），沒有覆寫玩家程式。

**P11 實走補充**：
- 下參道 ARM_PULL 4 次，臂長 3.9–4.95 m。
- 影格 32–128 的鏡頭壓得很低，玩家被石段遮住；鏡頭沒有進入石頭內部。

## 5. Gate、封存與回歸

### 本輪受影響的 Gate
| Gate | 結果 |
|---|---|
| SHRINE scene／scene-negatives／seal | 0 失敗 |
| SCHOOL scene／scene-negatives／seal | 0 失敗 |
| P9F | 0 失敗 |
| POP／ACT／CORE／OUTER／HUSE／HUX seal | 0 失敗 |

### 封存異動（limited reseal；`tools/seal_p11_r1.py`、`tools/seal_cascade_children.py`；前後 hash 都記在各封存的 `reseal_history`）
| 封存 | 異動 | kind |
|---|---|---|
| P9 R4-2 `p9r42_seal.json` `61d9d73d`→`31675649` | 只換 frozen `verify_village_v2_shrine_grove.gd` 的 hash | `P11_R1_WALKABLE_SURFACE_VERIFIER_CORRECTION` |
| P9 R4-3 `p9r43_seal.json` `f2a226d3`→`a35c45b9` | 只換 frozen `verify_village_v2_school_yard.gd` 的 hash | `P11_R1_NPC_DYNAMIC_VERIFIER_CORRECTION` |
| P9 FINAL `p9_final_seal.json` `c327c4c2`→`caa23b4b` | 只更新 sub_seals R4_2／R4_3 的 hash，並加一筆 events | `P11_R1_CHILD_R4_2_R4_3_UPDATE` |
| P10 R3b／R3c／R3d／R3e／R4／R4b | 只更新 child_seals 的 hash（這幾份封存把 P9 FINAL 或彼此當作子封存，逐層連動，6 輪後收斂）；封存內容不變 | `P11_R1_CHILD_P9F_CASCADE` |

以下內容都沒有變更：生成器、overlay、地面 shader、ART_REVIEW 圖、NPC、場景。

### 全量回歸
見 §6（穩定候選版跑一次）。

## 6. 全量回歸（穩定候選版）
`regression/full_regression.log`（2026-10-10 14:41–16:11，**143 項**；新增 2 項：SHRINE／SCHOOL 場景級反向）：**140 PASS／3 FAIL**。

| FAIL | 分類 | 說明 |
|---|---|---|
| terrain gate：載入 3556 ms，上限 3000 | Pre-existing | 歷次都在 3.5–3.9 s → P12 |
| P5 asset reset：違規 421 | Pre-existing | 筆數不變，不擴充白名單 |
| P8 runtime budget：High_overlook GPU Δ +4.07 ms，上限 4 | Pre-existing | 本來就在門檻邊緣跳動（P10 CLOSEOUT 實測 3.97–4.02，R5b.1 之前就是 3.99）。P11 沒有改任何場景或渲染內容，只動了驗證器、封存與工具。P10 最終回歸那次是 ✓ → P12 |

- **P9 R4-2 神社、P9 R4-3 寺子屋**：P10 時兩項都是 FAIL，本輪 scene gate、scene-negatives、seal **全部 ✓**。
- **本輪新引入的失敗：0。**

## 7. 剩餘風險
1. **1-3（以及 187 件會被爬上去的構件）**：等控制器負責 session 修改。改好之前，玩家走路會爬上店前長凳與板凳。
2. **下參道相機被拉近**：等相機 session 處理。
3. **V2 → 其他地圖的落點仍是 (0, 40, 0)**：等 main.gd 負責 session 處理。
4. **建物大多沒有可進入的門**：入口測試都停在正面牆前，這是設計上的現況，本輪不處理。
5. **其他未覆蓋範圍**：
   - 村內沒有 navmesh。
   - 窄路地（寬 1.3 m）可以通過，但需要側移。
   - 封存的 P7 河岸 gate 實走（RBG）沒有用其他 step 值重測，因為不能改封存工具。
