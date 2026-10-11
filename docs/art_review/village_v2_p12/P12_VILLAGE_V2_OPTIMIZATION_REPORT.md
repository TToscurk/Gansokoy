# P12 — Village V2 Optimization Report（2026-10-11）

狀態：送驗收（STOP）。畫質無退化：沒有改任何網格、材質、植被、建築、NPC 數量或位置。

## Wave 1 — 進村載入（commit `ed38e39`）

**根因（實測）**
- `village_v2.tscn` 的 load 約 4.0 s。大部分是 7.35 MB 文字場景的解析：轉成二進位約 2.95 s；Districts 內有 18,145 個建築 MeshInstance3D。依使用者裁定**不改場景結構**，Districts 二進位子場景保留為候選方案。
- 加入場景樹約 2.5 s，其中 **2.46 s 來自 Population**：51 個 NPC 的 `_ready` 各自對整棵樹（87,143 個節點）做一次 `find_children("SpringArm3D")`，每次約 46 ms，合計約 2.35 s。

**修正**
- `scripts/npc_population_actor.gd`：同一個 process frame 只掃描一次，結果共用。同一 frame 內新加入的 SpringArm3D 由 `node_added` 補進快取。
- NPC 的相機排除、行為、人數、位置都不變。
- R3b limited reseal（`P12_W1_SPRINGARM_SCAN_ONCE_PER_FRAME`），child seals 連動更新 R3c→R3d→R3e→R4→R4b；封存雜湊比對 0 不符。

| 量測（headless，同機） | Before | After |
|---|---|---|
| 村加入場景樹（同步 add_child） | 2524 ms | 202 ms |
| Population 子樹加入 | 2462 ms | 102 ms |
| main.gd `load_map("village_v2")` 整體 | 7595 ms | 3928–4185 ms |
| terrain gate（只量 load＋instantiate） | 3634 ms | 3691 ms（未變，仍 FAIL） |

- 驗證：POP scene 的 SpringArm 檢查 PASS（貫穿 NPC 的相機臂 4.57 m，等於排除 NPC 後的 4.58 m）。
- 量測限制：每次都是新的 Godot 程序，但作業系統磁碟快取狀態無法控制，不是嚴格的冷啟動。依存資源逐一 load 的 16.6 s 不可信：載入結果沒有被保留，可能重複載入，所以不採用這個數字。

## Wave 2 — P5 白名單 421 筆（未修改）

工具：`tools/p12/audit_p5_whitelist.gd`，判定邏輯與 gate 相同，可逐筆列出。依賴閉包共 1860 個，違規 421 個，**全部檔案都存在**。

| 分類 | 數量 |
|---|---|
| P9／P10 kit 檔案，**已逐檔列在封存雜湊中且雜湊一致**（mise／street／market／kiri／school／suzu／waterside／geidon／humanuse／tower 等 kit、NPC 資產庫、村用 NPC 腳本） | 382 |
| garden_kit 的 mesh（kit 目錄已由 P9 R4 封存，但 mesh 沒有逐檔列入） | 38 |
| `shaders/sky_daynight.gdshader`（共用天空，已知獨立問題） | 1 |

- **根因**：這是 registry 落後，不是資產錯誤。P9／P10 新增的 15 個 kit 與 NPC 庫已由各自的封存管理，但沒有登記進 `village_v2_asset_registry.json`。
- **修正數：0**。依「不得直接加白名單」以及先前「不擴白名單」的裁定，沒有修改。
- **建議**：以「每個 kit 引用其封存檔作為 gate 證據」的方式補登 registry。需要使用者授權後再做。

## Wave 3 — P8 高視角（未修改）

量測：同一程序，ON／OFF 交替 3 輪，每態暖機 60 幀、量測 150 幀，取中位數。

| 鏡位 | GPU Δ | 上限 |
|---|---|---|
| High_overlook | +4.03／+4.08／+4.09（本次）；整合回歸 +4.03 | 4.00 |
| T1_eye | +5.59 | 6.00 |
| 其他三個鏡位 | +1.79–+2.22 | 4.00 |

- **結論**：不是量測波動。數值穩定落在約 +4.05 ms，比上限多約 0.05 ms，可重現。render CPU Δ +1.5 ms，主要是 GPU 端；P8 增加約 1.9M primitives 與 1535 draws。
- 只為 0.05 ms 修改 P8 的植被或材質，違反畫質保護規則，所以照停止條件**不修改**，數據留存。

## 最終整合回歸（只跑一次）：139 PASS／6 FAIL

| 失敗 | 分類 |
|---|---|
| terrain 載入 3691 ms | 已知（P12 Wave 1：結構方案已延後） |
| P5 白名單 421 | 已知（registry 落後，見 Wave 2） |
| P8 COST High_overlook +4.03 | 已知（見 Wave 3） |
| **P9 R4-4 WATER plan**：`wk_reed_s@(329.7,−47.2)` 落在動線內 | **新發現，源於 P11（R2C 或更早），不是 P12** |
| **P9 R5-4 ENV plan**：MeadowP9 規劃株 114574 ≠ 封存 114105 | 同上 |
| **P10 R4b HUX plan**：`015_mk_tsumini`／`016_hu_seoikago` 位置與 snapshot 不符 | **源於 P11 R2D 農田支線** |

新發現三項的佐證：
- 只把 `farmland_p8.scn` 換回 R2D 前的版本：HUX 的 snapshot 不符消失，但 WATER／ENV 仍 FAIL。
- 只把 R2C 的 4 條道路換回原版：三項都仍 FAIL。
- 推測 WATER／ENV 來自 R2C 的河岸 RB_11_-7 重烘，或 R2B 的參道燈籠撤基壇。**未驗證**。
- 這三個 plan gate 會依目前場景的幾何重算擺放。P11 R2C／R2D 時我只跑了依存層的 scene gate，沒有跑這三個 plan gate，所以當時沒發現。這是我在 P11 留下的驗證缺口。
- 依「P12 不重開 P11」的規定，這輪**沒有修**。測試用的兩個替換檔案都已還原，雜湊確認一致。

## 審查
- 本環境無法啟動獨立的 GPT 代理逐 Wave 審查。本回合有一份 GPT 參考意見（MOA reference）。依該意見：沒有採用依存資源逐一 load 的 16.6 s；`add_child` 的數字不等同於單獨的 `_ready` 時間；修正只限「明確的冗餘處理」。這不是獨立代理對實際結果的審查。

## Git
- `ed38e39`：Wave 1 修正、reseal、`tools/p12/` 量測工具。
- 本報告與 `audit_p5_whitelist.gd` 另一筆 commit。
- 原本 staged 的 53 項不變；`main.gd` 與 `yoriichi_character.gd` 他 session 的修改雜湊不變；沒有 push。

## 待裁定／轉交
1. **P11 回歸缺口**（WATER／ENV／HUX）：要不要授權用 limited reseal 修正受影響的 plan gate 或擺放。
2. Districts 二進位子場景：候選方案，P13 建築重製後再評估。
3. P5 registry 補登 15 個 kit：需授權。
4. P8 High_overlook 多出的 0.05 ms：建議接受，或把上限調到 4.1 ms（需使用者裁定，我不自行放寬）。
5. P13 項目照原計畫。
