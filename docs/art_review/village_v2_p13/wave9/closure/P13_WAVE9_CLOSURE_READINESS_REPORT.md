# P13 W9 收尾：人間之里 V2 地圖整合與 CONTENT_FREEZE 準備度（等待使用者裁定）

> **狀態：等待使用者批准 CONTENT_FREEZE。** 自動測試通過不等於美術核准；EnrichW9P8（A8／B8）美術仍是 ART_REVIEW。
> 依使用者 2026-10-16 裁定執行：可寫 `village_v2.tscn`（期間不開編輯器）、掛 EnrichW9P8、恢復村南「→獸道」傳送點、劇情移植不在本次範圍（序章將重做）、district 管線混合檔合併提交。
> 寫入前確認：沒有任何 Godot 編輯器行程；寫入只有 `village_v2.tscn` +7 行、`village_v2.meta.json` 1 筆 portal。

## 0. 結論

**地圖內容可以進入 CONTENT_FREEZE**，沒有剩下會阻擋地圖收尾的問題。
- 26 段主路線（主街 9 段、住宅巷 10 段、稗田邸接近 1 段、任務錨點前 6 段，共 2.27 km）用真玩家輸入走完：0 卡住、0 失去接地、SpringArm 沒有嚴重縮短。
- 除錯層在正常遊玩時看不到了（可見 Label3D 39→0、區域輪廓 7→0、錨點標桿 8→0），編輯器裡照舊可見。
- 從獸道進村的落點修好了：之前落在地圖西北角 (0.3, 22, 0)，現在落在村南入口 (220.8, 0.2, 169.6)；V2↔獸道來回用真輸入（走進傳送區＋按 portal_enter）實測通過。
- 回歸總表 147 項：143 ✓、4 ✗。4 個 ✗ 都查清楚了：2 個是收尾前就有的，1 個是稽核工具的歸屬錯誤（已修，修後全過），1 個是計時造成（固定步長重跑，收尾前後完全相同、PASS）。

## 1. 已整合 vs 實驗／未掛載

| 內容 | 狀態 |
|---|---|
| EnrichW9P8（Phase 8 A8 稗田邸西＋B8 東北聚落，154 件） | **已掛進 `village_v2.tscn`**（EnrichW9P4 之後）；`verify_w9p8.gd` 掛載模式 43 PASS／0 FAIL；美術 ART_REVIEW |
| DevLayerGate（`maps/village_v2/scripts_p13/dev_layer_gate.gd`） | **已掛**（root 最後一個子節點）；`attach_dev_layer_gate.gd --check` OK；拆掉可逐位元還原（副本實測） |
| 村南「→獸道」傳送點 | **已恢復**（`village_v2.meta.json` 1 筆 target=beast_path、`gen_village_v2.gd::_write_meta` 同步，重生結果一致） |
| 稗田邸 1F／香霖堂傳送點 | 仍停用（P11 R2B 裁定；這兩張圖的回程仍指向 slice） |
| B8P（Phase 9 Blender 試點） | **未掛載**，隔離實驗（依裁定） |
| DistrictB8（B8 管線示範 overlay） | **未掛載**（與 EnrichW9P8:ZoneB8 同範圍，不可同時掛） |
| 劇情互動（MQ07–MQ12） | 仍在 slice；依裁定留給序章重做 |

## 2. 主路線可玩性（`evidence/smoke_disk.json`，磁碟上的正式場景，`--map=village_v2` 正常載入路徑）

| 群組 | 段數 | 長度 | 結果 |
|---|---|---|---|
| 主街（EntranceRoad、MainStreet、CrossStreetSouth／Mid、HillFootStreet、HillApproach、RiverNorthPath、DragonBridgeRoad、RiversidePath） | 9 | 1,190 m | 全 PASS |
| 住宅巷（WestAlley、WestLane、WestBankLane、MidLane、SWLane、NWLane、NWBranch、NELane、NENorth、NESouth） | 10 | 934 m | 全 PASS |
| 稗田邸接近（中橫街東端→FarmPath_1→FarmPath_4→門前） | 1 | 66 m | PASS |
| 任務錨點前（大鳥居、守衛、寺子屋玄關、鈴奈庵、鯢吞亭、稗田邸門） | 6 | 77 m | 全 PASS（都走到 0.00 m） |

- 全程 2,185 個樣本：BLOCK 0、失去接地 0 幀、單幀跳動 > 0.4 m 0、SpringArm 重度縮短 0（最短 5.29 m）。
- 換圖（`evidence/portal_walk.log`、`smoke_disk.json` transitions）：V2 → beast_path 落點 (0.0, 0.3, 2.0)；beast_path → V2 落點 (220.8, 0.2, 169.6)，都在地面上。
- 注意：另一個 session 在 2026-10-17 01:54 改寫了 `beast_path.tscn`／`beast_path.meta.json`（其南端 portal 仍指向 village_v2）。本報告的換圖實測在那之前完成；我沒有動獸道的檔案。

## 3. 剩下會阻擋收尾的問題

**地圖範圍內：無。**

範圍外、但序章重做時一定會碰到（不是本次凍結的阻擋項）：
- 劇情互動與導航點全在 slice（`maps/slice/slice_interactions.tscn`、`data/waypoints.json` 的 map 欄都是 slice）。
- `main.gd::load_map` 把 "village" 對應到 slice；正式開局 trail → slice。V2 只能從 `--map=village_v2` 或獸道 portal 進入。
- 從稗田邸 1F／香霖堂直接載入 V2 時落點仍是 (0.3, 22, 0)：這兩張圖的回程目前指向 slice，正常遊玩到不了，但改接 V2 時需要同時加 V2 端的對應 portal。

## 4. 延後的外觀問題（不阻擋）

| 項目 | 玩家可見程度（實測） | 備註 |
|---|---|---|
| 丘腳社寺灰盒（G1，18×9×12 m BoxMesh） | 從 HillFootStreet 可見，最近 26.6 m、74 個樣本 | 造型等 TASK E 裁定 |
| 跌水佔位 B7／F7（0.6 m×3 m 藍圓柱，#9） | B7 從 WestLane 最近 56 m；F7 從入口道路最近 108 m | 不在任務錨點附近；改水體需另行授權 |
| A8／B8 美術（#30） | — | ART_REVIEW，不再打磨 |
| EnrichW9P8 構件碰撞與 RNE 宅灰盒碰撞重疊 0.026–0.066 m | 實走不受影響 | 貼牆設計；稽核工具已正確歸屬 |
| W9 kit 137 個網格未登記進 P5 asset registry | — | 技術債；不放寬白名單 |
| 場景 load+instantiate 4.1–4.2 s（參考值 3 s） | — | 收尾前後相同 |
| B8P 管線的 draw call／LOD 調查 | — | 延到下一個開發週期 |

## 5. 回歸總表（`evidence/regression_summary.txt`、`regression_full.log`）

147 項：143 ✓、4 ✗，耗時 88 分。4 個 ✗ 都做了收尾前／後對照：
1. **terrain gate**：只有場景載入時間超過參考值。收尾前 4212 ms、收尾後 4074 ms → 原本就有。
2. **P5 asset reset**：137 個 w9_kit 網格不在白名單。收尾前同樣 137 個 → 原本就有。新增的 2 個依賴都在白名單內。
3. **場景擺放稽核**：稽核把第三者碰撞（EnrichW9P8 貼牆構件、ArchW9R2P13 的柱）記成「建物對建物穿插」。已修正歸屬（門檻不變）。修正後 clean 207 PASS／0 REVIEW／0 FAIL，5 個反向／對照案例全部符合（舊版 aabbfp 不符的問題也一起消失，登記表 #27 結案）。細節：`evidence/place_audit_attribution.md`。
4. **P10 R3d 核心區人口 scene**：審圖鏡位 4_market_high 同模型 3 人（10→11 人）。只掛 EnrichW9P8 時 PASS，加上 DevLayerGate（就算讓它不隱藏）就 FAIL。原因是這項檢查以 render 幀數等待，行人在物理步上移動，任何載入差異都會改變行人此刻的位置。用 `--fixed-fps 60` 重跑：收尾前、收尾後都是 10 人、PASS。→ 計時造成，不是內容回歸；沒有改這個封存檢查。建議往後回歸總表這一項加 `--fixed-fps 60`（需使用者決定）。

## 6. 保護與完整性

- 原 53 個 staged 項目：`git diff --cached --raw` 與開工時逐位元相同（每次 commit 後都比對）。
- 封存檔：現行 30 個 seal、1155／1155 hash 一致；收尾改動的檔案都不在任何 frozen 表（`evidence/seal_check.txt`）。
- `village_v2.tscn` 只多 7 行（2 個 ext_resource、2 個 root 節點），沒有改既有內容、水體、封存幾何（`evidence/scene_and_meta_diff.txt`）。
- 沒動：`main.gd`（另一個 session 的未提交修改原樣保留）、`layout_v2.json`、獸道的任何檔案、`review_start.gd`、共享玩家／相機控制器。
- 沒有 reset、stash、push。

## 7. Commits 與檔案歸屬

| commit | 內容 |
|---|---|
| `393bfa4` | Phase 9 純產物：B8P manifest／overlay／隔離測試場景、Phase 9 報告與證據、登記表 Phase 9 條目 |
| `679a333` | district 管線 5 個腳本＋B8.json／district_b8.scn／district_b8_test.tscn（B8 初版 session＋Phase 9 修改，合併提交，訊息註明兩段來源） |
| （收尾 commit，見最後回報） | DevLayerGate 腳本與掛載工具、`village_v2.tscn` +7 行、`village_v2.meta.json`＋`gen_village_v2.gd` 的獸道傳送點、稽核歸屬修正、本報告與證據、登記表 #27／#28／#29 |

未解決的歸屬：無。本任務的檔案全部提交；其他 session 的未追蹤／已修改檔案沒有碰。

## 8. 需要使用者裁定

1. 是否批准人間之里 V2 進入 **CONTENT_FREEZE**。
2. 回歸總表 R3d 人口 scene 項目是否改用 `--fixed-fps 60`。
3. 延後清單（§4）的處理時機，尤其是丘腳社寺（TASK E）與跌水佔位（#9）。

## 9. 檔案

- `review/debug_layers_before_after.jpg`：除錯層 BEFORE／AFTER（同視點 3 組，`--map=village_v2` 正常載入）
- `evidence/`：smoke（磁碟／掛載前記憶體）、換圖、verify_w9p8、回歸、稽核歸屬、封存對照、場景差分
- `evidence/repro/`：`v2_smoke.gd`（主路線 smoke harness）、`smoke_legs.json`（由 layout_v2.json 道路中心線產生的 26 段）
