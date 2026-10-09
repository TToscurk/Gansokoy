# P10 R5–R6 回歸對帳與失敗分類（ROUND 2）

## A. 第一輪 128 項：10 FAIL 的對帳（使用者要求「找出第 10 項」）

第一輪報告寫「既知 4＋本輪造成 1＋Pilot 相關 5＝10」，但正文只把「既知 4」與「Pilot 5」列成清單，**第 10 項＝19-point walk** 只出現在「本輪造成 1（已修正）」的括號裡，所以看起來只有 9 項。逐行對帳如下（來源：`../../regression/full_regression.log` 第 9／20／25／34／45／115／247／250／255／258 行；基準＝P10 FINAL `docs/art_review/village_v2_p10_final/gate/full_regression.log` 的 4 項 ✗）。

| # | 回歸項目 | 分類 | 證據 | 現況 |
|---|---|---|---|---|
| 1 | terrain gate（含鋸齒坡、東岸、橋端、農田） | **Pre-existing Failure** | P10 FINAL 基準同一項 ✗（第 9 行） | 不變（本輪不處理） |
| 2 | P5 asset reset gate（白名單／Protected／封存） | **Pre-existing Failure** | P10 FINAL 基準 ✗（第 20 行）＝KNOWN_SCOPE_DEBT | 不變 |
| 3 | P8 runtime budget（五鏡位 A/B） | **Pre-existing Failure** | P10 FINAL 基準 ✗（第 44 行）＝PRELIMINARY／UNRESOLVED CLEAN BENCHMARK | 不變 |
| 4 | P9 R4-3 寺子屋周邊場景級驗證 | **Pre-existing Failure** | P10 FINAL 基準 ✗（第 114 行）＝R3d C20 巡回擋入口實走（跨層，驗證器 scope 修正待同意） | 不變 |
| 5 | P6 町家 Kit Asset Gate 回歸 | **Expected Pilot Seal Conflict** | `AlbedoPilotP10` 對 Pilot 24 棟的 Kit 材質做執行期 override → Kit Gate「無 override」規則抓到（`B_P_MKT_001 base_0 surface 0 override`…）。`proof_pilots_off.log`：關掉 AlbedoPilot／PropFix → ✓ | 保留衝突（不放寬 Kit Gate）；遷移方案見 `../r6a_kit_material_spec.md` |
| 6 | P10 R4 Human-Use Pilot 場景級驗證 | **Expected Pilot Seal Conflict** | `PropFixP10`：A2 背負い籠東移 1.0 m（使用者 D9 授權的最小位置修改）→ snapshot 不符 `PilotA/A2_dakkoku/006_hu_seoikago 位置／朝向`；st_hasa→v2 | 保留衝突；R4 snapshot 的 A2 1 件＋st_hasa_v2 參照需 ART_APPROVED 後 limited reseal |
| 7 | P10 R4 Human-Use Pilot 封存 | **Expected Pilot Seal Conflict** | 同上（封存 snapshot＝場景） | 同上 |
| 8 | P10 R4b Human-Use Expansion 場景級驗證 | **Expected Pilot Seal Conflict** | R4b gate 獨立驗 R4 的 50 件 snapshot 不變 → 同一件 A2 不符 | 同上（R4b 本身的 40 件不變） |
| 9 | P10 R4b Human-Use Expansion 封存 | **Expected Pilot Seal Conflict** | 同上 | 同上 |
| 10 | **19-point walk** | **Newly Introduced Regression（已修正）** | R6b 一の鳥居柱台碰撞（0.72 角、高 0.58）讓斜線通過的膠囊浮起 dy 0.50 m（`diag_walk19_before_fix.txt`）→ overlay 柱台ガード（r 0.52、資產不動）→ `rerun_affected_after_fix.log` ✓ dy 0.05 m | 已修（commit `2f617cd`） |

另：#6 的場景級檢查裡同時藏著一個 **Newly Introduced Regression**——A2 籠沈在地下 1.0 m（R4C gate 的地面射線打到籠自己的碰撞），已修（地面＝TerrainCollision，反向 N5），重驗 HUSE 只剩 A2 位置不符（＝Expected Pilot Seal Conflict）。

**沒有修改任何舊 Gate 來讓審查中的改動通過。** 5 項 Seal Conflict 用 `proof_pilots_off.log`（暫時把 AlbedoPilotP10／PropFixP10 設 enabled=false 跑 KIT／HUSE／HUX 場景級＋封存 → 全 ✓，還原後 village_v2.tscn 雜湊一致）證明是兩個 Pilot overlay 造成、不是封存內容損壞。正式解決＝美術核准後的合法封存遷移（R6a：`r6a_kit_material_spec.md`；R4c：R4／R4b snapshot limited reseal）。

## B. ROUND 2 全量回歸（130 項＝128＋RDB 2）：121 PASS／9 FAIL（`full_regression.log`）

| # | 項目 | 分類 | 證據／説明 |
|---|---|---|---|
| 1 | terrain gate | Pre-existing | base 載入 3707 ms ＞ 3000（P10 FINAL と同じ、P12） |
| 2 | P5 asset reset gate | Pre-existing | 違規 421（KNOWN_SCOPE_DEBT、白名單は広げない） |
| 3 | P9 R4-3 寺子屋周邊 場景級 | Pre-existing | R3d C20 巡回（跨層、驗證器 scope 修正待同意） |
| 4 | P6 町家 Kit Gate | Expected Pilot Seal Conflict | AlbedoPilotP10（ROUND 2 で不変） |
| 5 | R4 HUSE 場景級 | Expected Pilot Seal Conflict | PropFixP10 A2 1 件（ROUND 2 で不変） |
| 6 | R4 HUSE 封存 | Expected Pilot Seal Conflict | 同上 |
| 7 | R4b HUX 場景級 | Expected Pilot Seal Conflict | 同上 |
| 8 | R4b HUX 封存 | Expected Pilot Seal Conflict | 同上 |
| 9 | **P9 R4-2 神社周邊 場景級** | **Newly Introduced（R6b ROUND 2 の盛土の踊り場 × 封存 gate の地形基準の膠囊）** | 179 点中 40 点が RampCollision。ShrineApproachP10 を外すと 0／179＝PASS（`proof_r6b_off_p9r42.log`）。玩家實走は阻塞 0。舊 gate 不修改；選択肢は `../ROUND2_ART_REVIEW.md` §6 |

第一輪からの変化：19-point walk ✗→✓（修正済み）、P8 runtime budget ✗→✓（不安定な既知項目、今回たまたま通過＝改善とは扱わない）、P9 R4-2 ✓→✗（上の #9）。
