# P12 Final Cleanup Report（2026-10-12）

狀態：送驗收（STOP）。TASK B 已完成；TASK A 三項都已查到根因，其中一項需要使用者裁定才能套用。

## TASK A — 三項回歸失敗

隔離方法：每次只把一組檔案換回 P11 前的版本（暫存後還原，雜湊比對確認），重跑該項 plan gate。注意：`farmland_p8.scn` 是 Git LFS 檔，`git show` 拿到的是 pointer，所以必須改用 R2D 當時的實檔備份；換成實檔之後，前一份報告的部分推論隨之更正。

| 項目 | 根因（實測） | 實際場景 | 處置 |
|---|---|---|---|
| WATER `wk_reed_s@(329.7,−47.2)` | R2C 重烘河岸 RB_11_-7（P7 石積頂點，是 waterside plan 的輸入），重算後的 plan 位置因此漂移。只換回 RB_11_-7 → PASS | 封存 overlay 的 202 個 wk_* 實物，用與 gate 相同的 `_blocked()` 判定：**0 個在通路內**。對應的實物 `120_wk_reed_s` 在 (328.75, −45.25) | 實物合法，**未修改**，保留 FAIL。只是 plan 重算與封存不一致，沒有真正的碰撞 |
| ENV MeadowP9 規劃株 114574 ≠ 114105 | R2D 改了 P8（撤除水車 1／3 高架樋、新增支線），草地 plan 的障礙輸入跟著變。只換回 R2D 前的農田實檔 → PASS | 封存 MeadowP9 實物 153,772 個 instance（非 headless 讀取）：落在 R2D 支線土渠外寬內 0、在道路面上 0 | 實物合法，**未重烘、未修改常數**，保留 FAIL |
| HUX 015／016 snapshot 不符 | 同 R2D。只換回農田實檔 → PASS | **真衝突**：`015_mk_tsumini` 的 LOD0 距 T0 支線可見網格 **0.339 m**，小於 R4 規定的 P8 水路禁區 0.4 m | 已驗證修正方案，但**尚未套用**，見下 |

**HUX 修正方案（已驗證、已還原、等待裁定）**
- 作法：用同一個生成器、同一個 seed 重烘（`HUX_ALLOW_REBAKE=1`）。只有 015／016 兩件往 x 方向移 0.25 m，其餘 38 件、朝向和 meta 都不變。
- 驗證結果：
  - 015 與支線距離變成 0.571 m，016 為 3.19 m。
  - HUX plan、negatives、scene 都是 0 失敗。
  - snapshot 只有這 2 件的位置不同。
- 阻礙：HUX `--seal` 有一項「A/B 與承認時 r3 審圖 plan 相差 ≤ 2 cm」的美術保護檢查，移動 0.25 m 一定會 FAIL。若要通過，只能改承認基準 `plan_r3.json` 或放寬容許值，兩者都等同修改檢查規則，所以我沒有做，已把 overlay／snapshot／seal 全部還原（雜湊一致）。
- **需要裁定**：是否接受這 2 件道具 0.25 m 的美術變更？若接受，要用什麼方式記錄（例如在 R4b seal 寫一筆使用者核准的位置例外，並讓 checker 對該例外驗證精確位置）。

WATER 和 ENV 的實物都合法，但修正方式只有兩種：重烘封存植被，或讓 gate 對準封存基準；兩者都超出「不重建 P9、不改檢查規則」的授權，所以兩項都保留 FAIL 和上述證據。

## TASK B — P5 421 筆登記（完成）

- 只使用各 seal 現行的 `frozen` 條目，不使用 reseal_history 裡的舊雜湊。重新核對結果：

| 來源 | 筆數 | 證據 |
|---|---|---|
| `seal_frozen` | 382 | 某個 seal 現行 frozen 中，同路徑、同 SHA-256 |
| `kit_manifest` | 38 | garden_kit mesh：`village_v2_p9r4_seal.json` 現行 frozen 鎖定 `garden_kit_manifest.json`，manifest 的 `deps` 內有同路徑、同 SHA-256 |
| `shared_runtime_dep` | 1 | `sky_daynight.gdshader`：由 `v2_allowed.shared_runtime` 中的 `scripts/sky_system.gd` 以 `SKY_SHADER` 引用；village_v2.tscn 的 ext_resource 也有引用 |
| 未能證實 | 0 | — |

- `village_v2_asset_registry.json` 新增 `v2_exact_files`，共 421 筆，每筆有精確路徑、SHA-256、來源類型、證據檔。**沒有新增任何目錄前綴。**
- `verify_village_v2_asset_reset.gd` 新增 `_exact_ok()`。必須同時滿足以下兩點才放行：
  - 路徑與雜湊都與登記一致。
  - 證據目前仍有效：seal frozen、seal 鎖定的 manifest deps，或 shared_runtime 腳本仍然引用。
- `tools/build_village_v2_asset_registry.py`：重新生成 registry 時保留 `v2_exact_files`。
- 結果：ASSET gate **0 失敗**，違規數 421 → 0。
- 反向測試（`--registry=` 暫存 fixture，正式檔未動），全部會 FAIL：

| 反向測試 | 結果 |
|---|---|
| 竄改 1 筆登記雜湊 | 違規 1 |
| 證據換成錯誤的 seal | 違規 1 |
| 刪除 1 筆 garden_kit 登記（同目錄、未登記） | 違規 1 |
| shared_runtime 證據換成不在清單內的腳本 | 違規 1 |

## Git 與保護
- `a96a5a9`：只讀診斷 probe。
- TASK B 與本報告：另一筆 commit。
- 原本 staged 的 53 項沒變；`main.gd` 與 `yoriichi_character.gd` 的他 session 修改，雜湊沒變。
- HUX 相關檔案已還原，沒有提交；沒有 push。
- 只跑了相關的 plan／scene／seal 檢查和反向測試，沒有跑完整回歸、沒有實走。

## 審查
這個環境無法啟動獨立的 GPT agent。本回合有一份 GPT 參考意見，已採用其中幾點：只用現行 frozen、不以 plan 新輸出直接當基準、不自動連鎖背書 seal。但它不是對最終 diff 的獨立 ACCEPT。

## 剩餘已知例外
- **地形載入 > 3000 ms**：Districts 結構方案延後。
- **P8 High_overlook +4.03–4.09 ms**：已接受的偏差，上限仍是 4.00 ms。
- **WATER／ENV plan gate FAIL**：實物合法；plan 重算與封存基準不一致。
- **HUX**：真衝突，修正方案等待裁定。
