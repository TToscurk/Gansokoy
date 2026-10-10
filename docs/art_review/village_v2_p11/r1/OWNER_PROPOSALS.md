# P11 R1 — 其他 session 持有檔案的修改提案（只提案、未修改）

使用者 P11 指示：「不要直接修改 Yoriichi 相機、角色控制器或 main.gd；如有衝突，先提出最小修改方案」。
本輪 Step 0 確認的現況如下：
- `characters/yoriichi/player_camera_adapter.gd`：最後修改日期 09-07，工作樹沒有變更。也就是說，相機 session 還沒做 pitch 修改。
- `yoriichi_character.gd`、`player_yoriichi.tscn`、`scripts/main.gd`、`scenes/main.tscn`：工作樹有其他 session 未提交的變更。本 session 一律沒碰。

## A. 角色控制器：step-up 會讓玩家走路時就爬上 0.4–0.55 m 的構件（B_P_MKT_003 店前台子的真因）
**檔案**：`characters/yoriichi/yoriichi_character.gd`
- 參數：`@export var step_height := 0.6`（第 532 行）
- 函式：`_try_step_up`（第 1728 行起）

**真因（實測）**：
- 店前「台子」是 P10 R2 StreetP10 的長凳 `046_sk_bench`。它的碰撞頂離地 0.51 m，下緣離地 0.09 m，就貼著店面。
- 玩家的 step_height 是 0.6 m，走路撞到它就會被 `_try_step_up` 抬上去。Kit Gate 的實走量到離地 0.43–0.51 m。
- 全村位在「離地 0.25–0.60 m」這個會被爬上去的區間內的構件碰撞有 **187 件**，其中 25 件在建物 1.2 m 以內（店前或門前）。證據：`diag/steppable.json`。

**step_height 比較**（`tools/diag_p11_step.gd`，只在記憶體中覆寫，檔案沒改。證據：`diag/step_compare.json`、`step_kit.json`、`step_low.json`、`step_walkcases.json`）：

| step_height | B_P_MKT_003 正面走入 | 市集西縁台 | 應通過：參道石段上／下、寺子屋踏石、稗田邸門、Bridge_02 端、Bridge_05、田埂、河岸石段 |
|---|---|---|---|
| 0.60（現行） | **爬上 0.51 m** | 爬上 0.49 m | 全部通過 |
| 0.45 | 爬上 0.51 m | 不爬 | 全部通過 |
| 0.40 | 爬上 0.51 m | 不爬 | 全部通過 |
| 0.35 | **不爬** | 不爬 | 全部通過；P8 ZONE 25 段＋FEEDER 0 失敗（`walk_step035/`） |
| 0.30 | 不爬 | 不爬 | 全部通過 |
| 0.00 | 不爬 | 不爬 | （不能上石段，僅供對照） |

**但是只把 step_height 降到 0.35 還不夠**。在全路線實走（`walk_step035/`）中：
- 走路撞到長凳後，「STUCK 側移」沿著長凳邊緣橫走，仍然爬上 0.51 m 長凳和 0.49 m 縁台。
- 0.40 與 0.45 直線走入也會爬上 0.51 m，表示 step-up 會**連續疊加**：第一次被抬起後，膠囊的圓底卡在箱子的上緣，下一幀被當成地面，再 step 一次。

**最小修改提案**（給控制器負責 session）：
1. `step_height` 0.6 → **0.35**。上表的應通過路段、P8 田埂（ZONE）與 FEEDER 都已實測可走。
2. 在 `_try_step_up` 開頭加上兩個條件，防止連續疊加：
   - 只有在 `is_on_floor()` 且地面法線與 UP 夾角 ≤ 15°（站在平面上，而不是頂著邊角）時才 step。
   - 落地後的實際上升量不得超過「step 前的地面高度＋step_height」，用 step 前的地面高度比較，而不是上一幀的高度。
3. 不用加碰撞，不用改封存構件。

如果負責 session 不改控制器，資料側的替代方案是：把「不該踩上去」的構件碰撞在其上方加高到 ≥ 0.75 m。不過這會動到 StreetP10、MarketP10、MarketWestP10、HumanUse 等封存，需要使用者授權，本輪沒做。

## B. 相機：參道下行被拉近（ARM_PULL）——整合需求
**檔案**：`characters/yoriichi/player_camera_adapter.gd`。相機 session 尚未修改，本 session 也不修改。

**實測（P10 R6b，`docs/art_review/village_v2_p10_rehab_impl/r6b1_shrine/CAMERA_HANDOFF_yoriichi.md`）**：
- pitch −0.18：參道下行有 55 % 的路程被拉近，共 5 次。
- pitch −0.35：被拉近只剩 5 %，1 次。
- 只有地形、沒有參道碰撞時，也有 73 % 被拉近。根因是 30° 坡道遇上 −0.18 的 pitch。

**P11 實走**（`walk_r1/`，正式 main.tscn F5 路徑，從獸道落點出發，pitch −0.18 固定）：
- 下參道 90 m 中 ARM_PULL **4 次**，都撞到 `ShrineApproachP10/RampCollision`，臂長被縮到 3.9–4.95 m。
- 影格 32–128 的鏡頭貼在石段上方、很低，玩家被石段擋住看不到（`review/s9_sando_down_sheet.jpg`、`s9_sando_down.mp4`）。
- 相機沒有進入石頭內部（vision 判讀：沒有背面或剖面）。

**其他 ARM_PULL**：全路線共 18 次，其中市集、市集西、住宅路地、寺子屋前共 14 次，都是狹窄處碰到建物或構件，屬正常的相機碰撞（`diag/walk_r1_events.json`）。

**整合需求**：
- 陡坡偏置：可行走面坡度 > ~20° 且朝下坡移動時，目標 pitch 平滑拉到約 −0.35；離開坡道後回到使用者自己的 pitch。
- 不得關閉相機碰撞。

**重現步驟**：

```
G="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
"$G" --path . --script res://tools/walk_p10_final.gd -- --review=kirisame --start=trail --pitch=-0.18 --route=res://tools/walk_p11_route.json --out=<dir>/
"$G" --path . --script res://tools/walk_p10_final.gd -- --review=kirisame --start=trail --pitch=-0.35 --route=res://tools/walk_p11_route.json --out=<dir>/
```

數 `walk_log.json` 裡 `events[kind=ARM_PULL]` 的 `seg=s9_sando_down`。

## C. main.gd：V2 → 其他地圖的傳送落點（MASTER AUDIT R5c-02，現況未變）
**檔案**：`scripts/main.gd` 的 `_place_player()`（第 1282 行起）。

**實測**（`portals/runtime_boundary_portals.json`，`tools/audit_village_v2_rehab_runtime.gd`，P11 版本加了返回測試）：

| 方向 | 落點 | 結果 |
|---|---|---|
| V2 → trail、hieda1f、kourindou | 一律 `(0, 40, 0)` | 自由落下 1.85 s 後著地，y 分別為 4.04／4.20／3.13，沒有落入虛空。原因是這三張圖的 portal 都指向 `slice`，沒有 `village_v2`。hieda1f 是室內圖，落點可能在屋頂上（未確認）。 |
| trail、hieda1f、kourindou → V2 | V2 對應 portal 旁 **4.0 m** | 從 1.18 m 高落下，0.30 s 內著地 → 可以安全返回 |

**最小修改提案**（給 main.gd 負責 session）：
- `_place_player` 找不到 `target == from_id` 時，改用別名表（`village_v2` ↔ `slice` ↔ `village`）再找一次。
- 還是找不到就用 `meta.spawn` 或第一個 portal，**永不使用 (0, 40, 0)**。
- Gate：落點離 portal ≤ 6 m，0.5 s 內著地，墜落高差 ≤ 3 m。

正式流程目前載入的是 `slice`。總計畫 §52 是刻意這樣設計的，所以這項提案不影響 `slice` 的落點邏輯。
