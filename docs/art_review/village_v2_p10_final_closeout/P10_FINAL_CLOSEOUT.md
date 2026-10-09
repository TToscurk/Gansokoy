# P10 FINAL CLOSEOUT（2026-10-10）

使用者 P10 FINAL CLOSEOUT 三項正式裁定的執行結果。本檔之後 **STOP**，下一個主要階段為 **P11 — Collision & Navigation**，見 `P11_HANDOFF.md`。
不再開新的 P10 美術工作包。

## 1. 裁定與狀態
| 項目 | 裁定 | 本輪結果 | 狀態 |
|---|---|---|---|
| R5c Boundary Closure | ART_APPROVED（Pilot） | 不變，`--seal` 重驗 0 失敗 | **SEALED**（`data/village_v2_p10r5c_seal.json`） |
| R5a Road Base 416 m Pilot | ART_APPROVED（Pilot） | 不變，`--seal` 重驗 0 失敗（含記憶體重新生成與封存的比對） | **SEALED**（`p10r5a`） |
| R6a Kit Material 24 Buildings Pilot | ART_APPROVED（Pilot） | 不變，`--seal` 重驗 0 失敗，KITM 與 Kit 反向 4 都 ✓ | **SEALED**（`p10r6a`） |
| R4c Straw Geometry Pilot | ART_APPROVED（Pilot） | 不變，`--seal` 重驗 0 失敗 | **SEALED**（`p10r4c`） |
| 1 主街店前台子 | TRANSFER TO P11 | 已列入 `P11_HANDOFF.md` §1；Kit manifest、`gate.json`、asset registry 維持現狀 | P11 |
| 2 R5b.1 灌溉 | 方案 B LIMITED APPROVAL | **已實作**：竜骨車 1 台，P8 limited correction＋P8 limited reseal，R4b 子封存跟著更新 | P8 已重封；**竜骨車外觀＝ART_REVIEW**；R5b（WaterLifeP10）**未封存** |
| 3 R6b.1 神社 | DEFER VISUAL FINALIZATION TO P13 | r8 與 R6b.1 Kit Pilot 都保留作比較候選；沒有加任何細節 | **未核准、未封存**（不冒充正式美術封存）；碰撞、平台、NPC、相機交給 P11；pitch 交給 Yoriichi 相機 session |

## 2. R5b.1 實作摘要（詳見 `../village_v2_p10_rehab_impl/r5b1_irrigation/impl/README.md`）
**單台竜骨車可以合理供水，沒有改用替代方案。**

**水位與尺寸**：
- 從水渠水面 −1.52 m 到落とし桝水面 0.288 m，必要揚程 1.81 m。
- 吐き口高 0.66 m，設計揚程 2.18 m。
- 傾斜 28.4°，樋長 5.17 m。
- 竜骨車之後一路自流，水位單調下降，直到內渠 0.078 m。

**正式移除**：
- 高架落とし樋、接頭箱、受け樋枕木、支柱：可見 6 群。
- 對應的碰撞形 3 個。
- 移除是在 P8 生成器裡做的，沒有用 runtime 隱藏。WaterLifeP10 也不再碰 P8 的任何節點。

**保留**：
- 水車 2 的純動力功能：WLF scene 實測輪下端移動 1.26 m，與下游方向的內積 1.000。
- 水車 1／3 不動。

**等價性**：P8 其他 8677 個節點逐一一致，其中 MultiMesh 1844 個，差異 0。

**FEEDER**：
- 0 失敗。
- 新增三項檢查：系統狀態（隱藏的部件、停用的碰撞、殘留部件）、水源連通、與其他圖層的干涉。
- 新增永久反向 3/3：runtime 隱藏、碰撞停止、殘留 Chute_0，三種情況都正確失敗。

**效能**：High_overlook 在 R5b.1 之前就是 +3.99 ms，貼著 4 ms 上限。
- 第一版竜骨車多了 35 個 draw，量到 4.00–4.02 ms。
- 把網格合併後，draws 比 R5b.1 前少 1。
- 定版兩次單獨量測是 4.01／3.97，全量回歸的那次是 ✓。
- 這屬於本來就在門檻邊緣跳動的問題，不放寬預算。

## 3. 本輪封存異動（old → new，全部記錄在 `reseal_history`）
| 封存 | 檔案雜湊 | 異動內容 | kind |
|---|---|---|---|
| P8 `data/village_v2_p8_seal.json` | `520b6f64…` → `afe60297…` | frozen 3 件：`village_v2_farmland_lib.gd` `382f57c4`→`68c2ad71`、`village_v2_farmland_visual.gd` `46527a6c`→`a873162a`、`gen/farmland_p8.scn` `0b995c38`→`8132313b`。其餘 5 件 frozen、24 張 ART_REVIEW 圖、6 件證據都不變；P8 status 不變 | `R5B1_IRRIGATION_SOURCE_RYUKOTSU` |
| R4b `data/village_v2_p10r4b_seal.json` | `f0cd1d54…` → `f5e8e817…` | 只改 child_seals 裡 P8 封存的雜湊。R4b 的 40 件、生成器、overlay 都不變，R4b scene gate 0 失敗 | `R5B1_CHILD_P8_UPDATE` |

**沒有改動的封存**：
- P7、P9 全部、P10 R1／R1b／R2／R3b–R3e／R4。
- R5c／R5a／R6a／R4c。
- 這些在全量回歸裡的 `--seal` 都 ✓。

**未封存但有改動**：
- WaterLifeP10（R5b）：`gen/water_life_p10.scn` `bef7cc58`→`0a3a251d`。
- `water_life.gd` 拿掉了 P8 隱藏邏輯。
- WLF gate 第 4 項與 N7／N8 一起更新。

**反向測試**：
- P8 `--seal` 篡改 → 偵測到 1 件。
- R4b `--seal` 191 檔一致。
- FEEDER-NEG 3/3。
- WLF 反向 9/9。

## 4. 全量回歸（`regression/full_regression.log`，2026-10-10 05:00–06:27，141 項）
**137 PASS／4 FAIL**。比上一輪多 1 項，就是新的 FEEDER 永久反向。

| FAIL | 分類 | 證據 | 去向 |
|---|---|---|---|
| terrain gate：載入 3588 ms，上限 3000 | **Pre-existing**（每輪都在 3.5–3.9 s） | log 第 7 行 | P12 |
| P5 asset reset：違規 421 | **Pre-existing**（筆數與整合時、ROUND 2 相同；R6a 那 19 筆已經不在） | log 第 18 行 | 不擴充白名單 |
| P9 R4-3 寺子屋 scene：145 點中 2 點被 R3d `C20_kozo_m01` 擋住 | **Pre-existing**（跨層） | log 第 117 行 | 驗證器 scope 修正待同意（P11_HANDOFF §4） |
| P9 R4-2 神社 scene：179 點中 40 點被參道 `RampCollision` 擋住 | **Newly Introduced**（從 ROUND 2 的 R6b 開始，未核准） | log 第 108 行 | P11 確定參道碰撞 → P9 R4-2 limited verifier correction／reseal；外觀交給 P13 |

**上一輪的失敗**：
- P8 FEEDER 已修好：修的是真正的場景狀態，不是放行。
- R4b `--seal` 在 run1 曾因 P8 子封存而失敗，已依前述的 affected-seal reseal 修好。

**run1 紀錄**：竜骨車合併網格前的第 1 次全量回歸，保存在 `regression/run1_before_drawcall_merge_full_regression.log`。
- 結果 135／6。
- 多出來的 2 項是 COST（T1 +6.16）與 R4b `--seal`。
- COST 之後單獨重測，T1 是 5.58–5.74，屬於雜訊；最後一次全量回歸是 ✓。

## 5. 帶入後續階段的技術債（明列）
- P5 白名單違規 421（既有）。
- terrain 場景載入 3.5–3.9 s（P12）。
- P9 R4-3 寺子屋 scene gate（跨層，驗證器 scope 待同意）。
- P8 COST 的 T1（5.6–6.2）與 High_overlook（3.97–4.02）兩個鏡位，都貼著門檻跳動（P12）。
- P9 R4-2 參道（P11 處理碰撞，P13 處理外觀）。
- 竜骨車可讀性 2–4/5（P13）。
- 水車 1／3 的揚水前提（暫不修改）。

## 6. 範圍遵守
- 沒有 push。使用者原本 staged 的 53 項不變。
- `main.gd` 與玩家相機程式都沒動。
- 51 名 NPC 不變。
- 沒有開始新的 NPC、Human-Use 或全村建築工作。
- 沒有改任何舊 Gate 讓失敗消失：FEEDER 原有項目全部保留，只新增檢查。
