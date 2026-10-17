# P13 W9 FIX：建築碰撞替換——最終驗收與凍結前收尾報告

日期：2026-10-17　狀態：**FIX_REVIEW（等待使用者裁定 1 項殘留）**　範圍：人間之里 V2 `ArchW9R2P13` overlay 的碰撞與編輯器／執行期一致性。
本報告不宣告 CONTENT_FREEZE，不屬美術階段（可見節點無變更，非 ART_REVIEW 對象）。

## 1. 為什麼改（舊「overlay 只准柱子碰撞」規則的變更理由）

W9R2 重做了 46 棟的正面與屋頂外觀，但每棟 body 仍是 Kit 外形的單一 BoxShape3D。結果 22 棟出現：新的低屋頂上方 1.0–3.6 m 有看不見的箱（相機撞空氣）、新開的店面／前庭／庭院被箱封住（看不見的牆 3.1–3.6 m）、新二樓的牆沒有碰撞（0.6–3.0 m）。body 的箱屬共用場景 `village_v2.tscn`，不改；改在 overlay 內放「由外觀導出、登錄在 `collision_fit.json`」的 `<id>/Shell`，overlay 啟用時才與 body 的原箱交換。使用者 2026-10-17 Decision 1 批准，`verify_w9r2.gd` 註解記錄同一理由。

## 2. 交付內容

| 項目 | 值 |
|---|---|
| 登錄 Shell | 22 棟／**401 箱**（`godot/assets/village_v2/w9r2_arch/src/collision_fit.json`） |
| 生成 | `w9fix_colfit.gd`（外觀→箱）→ `w9fix_colfit_post.py`（整形＋tier 5 定點修正）→ `build_w9r2.gd`（bake 成停用的 Shell） |
| 啟用 | `arch_w9r2.gd`：`_ready` 同步交換（讀檔不推人）、`_restore`／PRE_SAVE 還原、POST_SAVE 重套；編輯器與遊戲一致 |
| overlay 非 Shell 節點 | 與修正前逐節點比對差 **0** |
| `village_v2.tscn` | 與 HEAD 相同（未改） |

## 3. 驗證結果（全部為 401 箱的最終資料）

| 檢查 | 結果 | 證據 |
|---|---|---|
| `verify_w9r2.gd` | **647 PASS／1 FAIL**；反向案例 **49/49**（原 36＋新 13：Shell 缺失／位置／旋轉／重複／未登錄箱／未登錄 Shell／layer；同時啟用／啟用後原箱仍開／兩邊皆關／存檔狀態 Shell 開） | `evidence/verify_w9r2.txt` |
| 唯一 FAIL | `village_v2.tscn` 自 0ca148f 起 +16 行（上限 9）。**既有基準例外**，與本修正無關，門檻未放寬 | 同上 |
| 模擬編輯器 overlay gate | 15/15 | `evidence/verify_editor_tool_overlays.txt` |
| 庇柱碰撞 | 19/19 | `evidence/verify_w9r2_posts.txt` |
| 除錯層 gate | OK | `evidence/dev_layer_gate_check.txt` |
| 生命週期（正式 main・真 controller） | **42/42**：初次載入／讀檔落點 5 處（不推人）／離村到 beast_path 再回村／enabled 反覆 ×3；每段核對 layer/mask、形狀、物理查詢 | `evidence/lifecycle_real.txt` |
| 真 Godot 4.7.2 編輯器（MCP，拋棄式副本） | 開啟→存→重載→存→重載：Shell 有效 391/391、原箱有效 0、衝突 0、layer/transform 不符 0；語意比對 91,002 節點差 **0**；從編輯器執行副本 game_eval 同樣 0 衝突。於 391 箱資料執行；之後只在 JSON 多 10 箱，啟用程式碼未變，箱數／狀態由上兩列在 401 箱重驗 | `evidence/editor_real_mcp_snapshots.json`、`editor_semantic_compare.txt` |
| 真 controller 走路 | 46 段 **40 PASS／6 FAIL**，與 391 箱時逐段相同。4 段既有（MKT_004／005／015 沿牆線、MXC_007 porch_gap 封存道具），2 段 = MXC_004 已接受限制 | `evidence/walk_real_controller.txt` |

## 4. 已接受的限制

- **MXC_004 凹入門口**（使用者裁定：裝飾、不可互動入口）：門凹地板離地 0.41 m（玩家可直接跨上的高度 0.35 m），要跳才進得去；碰撞門寬 1.10 m、可見門寬 1.40 m（側柱每邊寬 0.12–0.18 m）。未改玩家 step height 或移動。日後任務若需要走進此門，必須重新處理。
- **`verify_w9r2.gd` 行數 FAIL**：既有基準例外（見上）。

## 5. TPS 相機實玩確認（使用者 Decision 2）

工具 `godot/tools/p13/w9/w9fix_cam_review.gd`：正式 main、真 controller（相機基準的 move 輸入）、真 CameraAdapter／SpringArm。每棟 3 條路線（正面 1.3 m、道路 3.0 m、背面 1.3 m）× 6 個臂向 × 2 個俯仰（−0.18 預設／−0.6 俯視）。同一段路先 BEFORE（原箱）後 AFTER（Shell）。逐格量：壁內（相機越過可見面）、玩家被擋、1 格內縮 ≥1.5 m、臂 < 2 m。

**第一輪（391 箱，6 棟 216 段）**：185 SAME、9 REG_SIG（連續壁內／被擋增加 ≥0.25 s）、9 REG_MIN（0.05–0.25 s）、12 SNAP+、1 BETTER。重現的明顯回歸：

| 位置 | 現象（AFTER） | BEFORE |
|---|---|---|
| MKT_030 道路 3.0 m／正面 1.3 m，臂朝店內（含 ±45°），預設俯仰 | 相機穿過開放店面上方的**垂れ壁**（y 2.00–2.75 無碰撞）進入店內屋簷下，連續 0.53–1.28 s；畫面約 65–70% 被屋頂內面與柱遮住，玩家只露出一部分 | 停在原箱前，視野清楚 |
| MXC_007 道路 3.0 m，臂 ±45° 朝店內 | 同樣穿過垂れ壁（y 2.40–2.70），0.73–0.88 s，屋頂內面＋梁遮住 55–60% | 清楚 |
| RSW_074 背面 1.3 m，臂朝內 +45° | 0.34 s，相機進入**鄰棟 RSW_075** 的屋頂（RSW_075 無 Shell，屬 Kit「屋頂無碰撞」慣例）；原本是 RSW_074 的舊箱擋住 | — |

**唯一一次定點修正（tier 5，依可見面採寸）**：MKT_030 正面垂れ壁 1 箱；MXC_007 正面垂れ壁 1 箱，加上左右**袖壁** 8 箱（見世兩側為實牆，牆頂順屋頂坡度分 4 段；先前 hull 交集把它們漏掉，屬 MISSING_COLLIDER）。不改生成規則、不動其他棟或相機系統。採寸：`evidence/measure_hangwall.txt`。

**第二輪（401 箱，2 棟 72 段）**：在第一輪重現的同一位置、同一移動中重新拍攝，AFTER 的臂長等於 BEFORE（1.85／3.05／4.28 m），不再進入建物（`shots/v17_*`）。

**殘留（需裁定）**：

| 位置 | 現象 | 分類 |
|---|---|---|
| **MKT_030 正面 1.3 m（局部 lx 0.49，世界約 (275.6, 1.35, −75.1)）**，臂正朝店內、預設俯仰 | 玩家站在店前（被道具擋停），轉相機看街：臂高約 1.94 m，從垂れ壁下方的**開放店面開口**進入店內，臂 1.32 → 3.01 m，畫面約 70% 被遮。連續 0.45 s（站著不動則持續） | 實玩可見的**中度**相機遮擋；不擋移動、不擋進度。已用完唯一一次修正，**未再修** |
| RSW_074 背面 → RSW_075 屋頂 | 0.34 s，位於後巷 | ACCEPTED LIMITATION（鄰棟 Kit 慣例；修正需動無關建物，未授權） |
| SNAP+（1 格內縮 ≥1.5 m） | MXC_007 36 段合計 7 → 16 次，都是單格事件，沒有持續遮擋；CameraAdapter 設計就是即時內縮 | 無害 |
| MKT_015、RSW_076、MXC_005 | 沒有 REG_SIG；REG_MIN ≤ 0.15 s | 無害 |

合成相機樣本（probe，22 萬組）：變差 786（v12）→ 705（v16）→ **475**（v17），改善 3,772；隱形牆全村 44→17、穿入可見幾何 206→184，與 v16 相同（定點修正未產生新的行走問題）。`evidence/probe_v17_classification.txt`。

## 6. 效能（輕量比較）

- overlay `.scn` 載入：HEAD 1.08 ms → 6.69 ms；instantiate 0.78 → 4.11 ms（178 → 591 節點，為 401 箱前的量測，差 10 個節點可忽略）。村莊整體載入 4,561 ms，增加約 0.2%。
- 物理查詢（22 棟周圍 4,004 點，玩家 capsule cast_motion＋rest_info，3 次中位數）：6.21 → 7.33 µs／組。玩家每格只做數次此類查詢，增加 < 0.01 ms。
- 遊玩中 physics process 時間：同時有兩個 Godot 在跑，雜訊大於差值（兩次分別為 +0.16 ms 與 −3.4 ms），不作結論。
- 判定：沒有回歸證據，不開最佳化階段。

## 7. 檔案

程式／資料（同一個 commit）：

- `godot/maps/village_v2/scripts_p13/arch_w9r2.gd`
- `godot/maps/village_v2/scripts_p13/dev_layer_gate.gd`（前一輪編輯器／執行期一致性修正）
- `godot/maps/village_v2/gen/arch_w9r2_p13.scn`
- `godot/assets/village_v2/w9r2_arch/src/collision_fit.json`
- `godot/tools/p13/w9/`：`attach_dev_layer_gate.gd`、`build_w9r2.gd`、`verify_w9r2.gd`、`w9r2_lib.gd`、`walk_w9r2_real.gd`、`verify_editor_tool_overlays.gd`、`w9fix_colfit.gd`、`w9fix_colfit_post.py`、`w9fix_probe.gd`、`w9fix_lifecycle_real.gd`、`w9fix_cam_review.gd`、`diag_w9fix_collision.gd`、`diag_w9fix_profile.gd`、`shot_w9fix.gd`，以及已存在的 `.uid`

證據：本資料夾（`evidence/`、`evidence/repro/`、`shots/`）。完整原始記錄在 `work/w9_collision_fix/`（已 gitignore）。
