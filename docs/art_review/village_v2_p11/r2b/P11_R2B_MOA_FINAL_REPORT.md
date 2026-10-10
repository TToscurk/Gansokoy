# P11 R2B — MOA FINAL REPORT（2026-10-11）

狀態：**送使用者驗收（STOP）**。視覺部分只到 ART_REVIEW。

## 1. 各 TASK 狀態

| TASK | 狀態 | 結果 |
|---|---|---|
| 01 V2 對外傳送 | **DONE** | `village_v2.meta.json` 的 `portals` 已清空，所以 `main.gd` 不再生成任何 Portal Area3D。原 3 個座標保留在 `portals_disabled_p11r2b`，供日後參考。場景的 `Portals` 規劃標記改為 `visible=false`，節點保留，sightline 工具仍可使用。生成器 `gen_village_v2.gd` 已同步修改。開發出生點 `spawn (224,160)` 保留。`main.gd` 屬其他 session，未改動。候選 C 未整合。 |
| 02 雙層／浮空道路 | **BLOCKED（需裁定封存 reopen）** | 根因已確認，並已實作修正後再撤回，見 §3。 |
| 03 茶屋少女喝茶循環 | **DONE（ART_REVIEW）** | 根因：Activity overlay 把 Drink clip 直接替換到 `idle` 槽，而且是依指派表（路徑）永久替換，與情境無關。現在預設播放 Idle，每 25–45 秒才喝一次（第一次在 6–20 秒），杯子只在喝的時候顯示。三位茶屋角色（W3／C17／O8）共用同一份程式。 |
| 04 NPC 轉身 | **DONE（ART_REVIEW）** | 根因：`rotate_toward` 對角度值做線性逼近，目標跨過 ±π 時會繞遠路，最大接近 1 圈；而且角色是在 Idle 狀態下原地轉。改為最短弧（`angle_difference`），轉身期間播放 walk 踏步，轉完才切回 Idle。巡邏路線、人數、速度都不變。 |
| 05 水車 1／3 水道 | **PARTIAL（報告，未改）** | 見 §4。 |
| 06 石燈籠接地 | **DONE（ART_REVIEW）** | 參道 6 座燈籠原本放在 0.9 m 見方的水平基壇上，基壇已撤去，燈籠直接落在土面。計算方式：四角最低點 +0.09，且不高於中心，再埋入 0.03。gate 已改為「谷側浮起 ≤0.09、山側埋入 ≤0.6」，反向案例「浮空 0.4 m」仍保留。重建後 SAN 0 失敗。 |
| 07 Auto-Step 候選 A | **BLOCKED BY OWNER** | `yoriichi_character.gd` 仍有其他 session 未提交的修改（+225 行）。patch 已用 `git apply --check` 確認可以直接套用。 |
| 08 相機候選 B | **BLOCKED BY OWNER** | `player_camera_adapter.gd` 沒有移交給本 session。patch `--check` 通過。 |
| 09 小型異常 | **未處理** | 這次沒有順手確認的機會，列入技術債。 |

## 2. 實際修改的檔案（Claude 為唯一寫入者）

- `godot/data/village_v2.meta.json`、`godot/tools/gen_village_v2.gd`、`godot/maps/village_v2/village_v2.tscn`（只加了 `Portals visible=false` 1 行）
- `godot/scripts/npc_activity_overlay.gd`（TASK03）、`godot/scripts/npc_population_actor.gd`（TASK04）
- `godot/tools/village_v2_shrine_approach_lib.gd`、`godot/tools/verify_village_v2_shrine_approach.gd`、`godot/maps/village_v2/gen/shrine_approach_p10.scn`（TASK06 重建；ShrineApproachP10 原本就沒有封存）
- 封存（limited reseal，並寫入 `reseal_history`）：R3b／R3c 各自更新 frozen 的 NPC 腳本雜湊；R3d 的 `verify_village_v2_population_core.gd` 做 limited verifier correction，只放寬「Idle 期間杯子隱藏」這一點，喝的期間杯子隱藏仍判違規。child_seals 依序連動更新 R3c→R3d→R3e→R4→R4b。全部封存雜湊比對 0 不符。
- 只修改工具：`walk_village_v2.gd`、`walk_p10_final.gd`。傳送停用後，改從 `meta.spawn` 進入 V2。
- 新增：`godot/tools/p11r2b/`（探針、截圖、reseal 腳本）

## 3. TASK02 道路：根因與為何撤回

- 實測方式：用頂點對地形碰撞射線取樣。主街、巷道、田埂道的路面都在地形上 +0.03～+0.13 m，屬正常範圍。浮空集中在河、水渠邊的 7 條路：RiversidePath 最高浮 **0.59 m**（39 個點超過 0.15 m）、HillFootStreet **1.46 m**（橋頭附近）、RiverNorthPath 0.35 m、CrossStreetMid 0.35 m，其餘 ≤0.17 m。
- 根因：`gen_village_v2.gd _roads()` 生成的路面帶，橫斷面是沿中心線縱坡的水平面；`_grade` 整地發生在水道下切之前，所以岸坡上的路面外緣會懸在空中。把道路隱藏後，浮起的那一片就消失，因此確認是道路本身的幾何，不是地形材質，也不是 RoadBaseP10 造成的。
- 修正（已驗證有效）：浮起超過 0.15 m 的 76 個頂點往下貼到地形 +0.10。修正後 7 條路最大浮起 ≤0.135 m，低角度截圖不再看到懸空的路面。
- **撤回原因**：完整回歸發現，這些道路網格是封存層 **P7 河岸（RBG：烘焙 2766 ≠ 重排 2777）** 與 **P9 R5 Macro Ground（m9 地面 sha 改變）** 的生成輸入。修正道路等同重開 P7／P9 R5，超出指令「先確認最小影響範圍」的授權，因此已將 7 個 `road_*.res` 與生成器的道路部分還原。
- **需要使用者決定**：是否授權 P7＋P9 R5 limited reopen。若授權，要套用相同修正（工具已備：`tools/p11r2b/drape_floating_roads.gd -- --apply`），然後重新烘焙河岸並 reseal、更新 m9 ground digest。
- HillFootStreet 橋下那片藍灰色斜面在隱藏道路後仍然存在，屬於另一層（推測是 P7 護岸或橋台），尚未處理。

## 4. TASK05 水車水道（未改）

- 水車 1：`FarmlandP8/.../Feeders/Feeder_N0`，有高架落とし樋，最高 3.42 m，離水車 6–11 m。
- 水車 3：`Feeder_T0`，高架樋最高 3.24 m，離水車 6 m。
- 這兩處和 R5b 時水車 2 是同一個問題：下掛け水車（undershot）不能把水揚到 3 m 以上的受け樋。水車 2 已改用竜骨車。
- 兩條 feeder 仍各自供水給田區（N0／T0），所以「直接撤除」就會讓田區失去水源，不屬於「確定失去用途」的情況。依指令先報告，不另造系統。
- 可選方案：①比照 R5b.1，各加 1 台竜骨車，需要 P8 limited correction；②把高架段改為從上游水渠分水的地面渠；③保留現狀，列入 P13。這部分需要授權 P8 reopen。

## 5. GPT 獨立審查

本環境無法分派獨立的 GPT 子代理逐波審查。GPT 的參與僅限於開工前的方針參考（範圍控制、staged 保護、不得把未整合的 patch 當成完成），**沒有逐波 ACCEPT／REVISE**。審查角色實際由執行端以封存 gate 與回歸結果代替，這點如實記錄。

## 6. 畫面（`shots/`）

- 道路：`before_riverside_low_V0.png`（左側懸空路面，下方有空隙）／`before_riverside_low_R.png`（隱藏道路後消失）／`after_riverside_low_V0.png`（修正版，已撤回）／`before_hillfoot_low_V0.png`
- 燈籠：`lantern_Toro_00_side_low.png`、`lantern_Toro_00_tps.png`
- 茶屋：`w3_t00.png`、`w3_t10.png`（Idle，手上沒有杯子）
- 尚未錄製 NPC 轉身的短片，只有數值證據。

## 7. 測試

- 局部：`probe_npc_behavior.gd` 觀察遊戲內 90 秒。3 位喝茶角色的喝茶時間比例為 19–20%，各喝 2 次，杯子顯示不一致 0 幀。6 位巡邏角色每次折返最大轉角 179°，Idle 原地轉動 0 秒。
- 燈籠：`probe_lantern_ground.gd` 量測燈籠底部頂點與地面差，結果為 −0.15～−0.55 m，全部埋入，沒有浮空。
- 完整回歸（只跑一次）：143 項，136 PASS／7 FAIL。4 項是本輪造成，修正或撤回後**只重跑這 4 項：全部通過**（RBG、WALK 19/19、GC、CORE）。
- **最終：140 PASS／3 FAIL**，3 項全部是既知問題：terrain 載入 3634 ms、P5 白名單 421 筆、P8 High_overlook +4.07 ms（留給 P12）。

## 8. Git

- 一個本地 commit，只包含本輪的檔案，未 push。
- 使用者原本 staged 的 53 項：路徑與狀態比對無差異，未動。

## 9. 需要其他 session 處理

- 控制器 session：套用 `r2/patches/A_yoriichi_character_step.patch`。
- 相機 session：套用 `B_player_camera_adapter_slope_pitch.patch`。
- main.gd：候選 C 不需要套用，因為傳送已停用。

## 10. P12／P13

- P12：terrain 載入超過 3000 ms、P5 421 筆、P8 高視角 4 ms。
- P13：建築結構差異化、農舍與納屋、參道石階外觀、石材與地形交界、水車／竜骨車收尾、全村自然度。另加入：燈籠山側埋入 0.5 m 的外觀檢查、HillFootStreet 橋下斜面。
