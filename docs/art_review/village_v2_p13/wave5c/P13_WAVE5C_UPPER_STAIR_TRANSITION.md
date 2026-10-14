# P13 WAVE 5C — UPPER SHRINE STAIR TRANSITION

**最終狀態（使用者裁定）：TECH ACCEPTED / CONDITIONAL ART ACCEPTED。本階段技術工作結案，美術帶少量已記錄例外。STOP SHRINE STAIR ITERATION。**
範圍＝參道 s=89.85–99.50 m（原 r8 最後 20 個元素）。s=37.20–89.85 m 與左右乾砌石垣不動。接受 commit `a29a636`。

## 0. 最終裁定（優先於下方「ART_REVIEW 提交」各節）

### 0.1 保留
- 保留 s=89.85–99.50 m 的現有石階、邊石與地形適應方案（收窄 A 方案）。
- 不重新排列已驗證的 20 個階梯元素；**不啟動 W5D、不再做石階參數搜索**。

### 0.2 已記錄、尚未完成的視覺缺陷（移交 P13 最終環境美術清單，不宣稱已修正）
1. 最後約 0.5 m 右側步行幅（s≈98.7–99.5 m）**不是完整石鋪面**：可見面是 P1 地形，山坡土比踏面高 8–19 cm（`evidence/cover_after.log`：該段 11–13／17 格被石覆蓋）。可走性由 SWALK 與上下行走確認。
2. 部分邊石與笠石的收尾過於破碎（上段右側尤其明顯）。
3. 石階與土坡仍有局部突兀交界；已核准的 s≈70、83 m 側面也有類似交界（`diag/mid_vs_top.png`），屬同一類問題，應在 P13 的坡面／地形融合統一處理，而不是回頭單修石階。

### 0.3 植被處理——正式整合的必要條件
- 現況：兩株 ForestP9 植物（Near `4905_sasa_a`、`6695_tsutsuji_a` 與各自的遠景 LOD2 instance）**只在 `SandoPilotW4P13` overlay 啟用時**隱藏。overlay 已實例於 `village_v2.tscn`、`enabled` 預設 true、`_ready` 時 deferred 套用，所以正常進入 village_v2 的遊戲路徑會排除它們（W5C gate：歩行幅內可見植物 0；關掉 overlay 的反向案例會抓到）。
- 整合規則（之後任何人重生／重掛場景時都必須遵守）：
  - 重生 `village_v2.tscn` 後必須確認 `SandoPilotW4P13` 仍掛載、`enabled=true`、`suppress_plants` 非空；不得因 overlay 被停用或遺失而讓植物重新穿進石階。
  - 抑制清單以 `Vegetation/ForestP9/...` 的節點路徑與 MultiMesh instance index 記錄；**ForestP9 若被重烘，清單會失效**，必須由 `w5c_upper_plan.gd` 的 `intruders()` 重算並重建 W5C（W5C gate 會比對「儲存清單＝生成器清單」，不一致即 FAIL）。
  - **不得為了這兩株植物直接修改整個 ForestP9，也不得重烘森林層**；封存的 `forest_p9.scn` 維持原樣。
  - 若日後要把抑制改成「烘進場景」的永久方案，必須另案並經使用者同意（涉及 P9 R2 封存的限定解封）。

### 0.4 測試與保護
- 已有的局部 gate（W5C 26 項含 5 反向、W5B、W4 pilot、SAN plan／scene、SWALK、SHRINE、FOREST seal、P9 FINAL）與一次玩家上下行走已足夠；**不重跑七輪參數搜索、不跑全村回歸與長距離實走**。
- P1 地形、相機、Auto-Step 及其他 session 檔案未動；原 staged 53 項前後一致；不 push。

### 0.5 後續
- 停止參道石階迭代，不再自行開啟石階修正任務。
- 後續優先序：P13 剩餘道路、地形與村莊整體美術（上述 0.2 三項併入該清單）。

---

# 以下為原 ART_REVIEW 提交內容（歷史紀錄）

狀態（提交時）：**ART_REVIEW**。

## 1. 先查到的事實（BEFORE，r8 長踏石）

| 項目 | 結果 | 出處 |
|---|---|---|
| 這段是什麼 | 原 r8 的 `long`／`slab` 長踏石＋細石條，沒有擋土、沒有笠石、沒有 W4 的石垣 | `evidence/cover_before.log` |
| 地形穿過踏面 | 歩行幅 \|lat\|≤0.85 內 **15 格、最大 11.6 cm**（山坡側土比踏面高） | `gate_w5c.log` `[W5C-POKE]` |
| 伸入走道的植物 | ForestP9 Near 的 `4905_sasa_a`（s=91.4）、`6695_tsutsuji_a`（s=90.0）＋各自遠景 LOD2 的 1 個 instance | `veg_before.log` |
| 土草間隙 | 原設計：踏面之間本來就是長踏石＋縫；幾何問題：石端不收邊、山坡側被土蓋住 | 圖 `compare/` |

## 2. 做了什麼（只動這 10 m）

- **不重規劃**：原 20 個元素的 k 範圍、踏面高度、深度原樣保留（`w5c_upper_plan.gd`，W5B 已證實 `plan_flight` 不能可靠重排長踏石）。
- 用 W4 的石語彙重建這 20 個元素：厚石板、不規則邊、石垣＋笠石、石垣下的土裙（獨立 mesh seed 133601）。
- 山坡側地形比踏面高時，**把該側的石在那之前收窄**（`cap_l`／`cap_r`，向後漸變 0.45 m／級），而不是抬高階梯；碰撞契約不動。
- 兩個伸入歩行幅的植物在 **overlay 執行時可逆隱藏**（`SandoPilotW4P13.suppress_plants`；封存的 `forest_p9.scn` 一個位元組都沒動，`enabled=false` 即復原）。
- 共用 `village_v2_sando_w4_lib.gd` 的兩處新程式只在元素帶 `cap_l`／`cap_r` 時生效；下段 W5B 幾何逐頂點不變（見 gate）。

## 3. 驗證（只跑相關 gate，不跑全回歸／全村實走）

| Gate | 結果 |
|---|---|
| `verify_w5c_transition.gd`（新，26 項含 5 個反向案例） | **failures 0** |
| ‑ 已核准 s=37.2–89.85 的 W4Steps／W4Soil／W5Upper 逐頂點 | 與 HEAD（W5B）**bit-identical**（149361／34284／115668／32412） |
| ‑ plan fidelity | 20 個原元素、k 範圍與高度不變 |
| ‑ 看得見的石 vs 實際斜坡碰撞 | 無缺面、無退化；接點 s=89.85／內部／99.50 新增壞點 0 |
| ‑ 基石埋入 | 45 顆全部埋入 ≥ 0.203 m；無浮空 |
| ‑ 地形穿踏面（\|lat\|≤0.85） | **11.6 cm → 3.9 cm**（5 格；門檻 5 cm；階腳／後唇埋入不算穿出，定義見 gate 註解） |
| ‑ 植物 | 歩行幅內可見植物 0；關掉 overlay 反向案例能抓到 |
| `verify_w5b_integration.gd`（W5B gate） | failures 0（只改一處：移除範圍讀 W5C 的 END，見 diff） |
| `verify_w4_pilot` 34／`SAN plan` 10／`SAN scene` 6／`SWALK` 8／`SHRINE scene` 4／`SHRINE seal` 3／`FOREST seal` 2／`P9 FINAL` 6 | 全 PASS（`evidence/gate_*.log`） |

## 4. 一次短距離上下行走（真實玩家輸入；相機與 Auto-Step 未改）

`evidence/walk_w5c.log`
- 上行 s=86→99.6：到達、**離地 0 幀**、受阻 1 幀、單幀最大 dy 0.044 m
- 下行 s=99.6→86：到達、**離地 0 幀**、受阻 1 幀、單幀最大 dy 0.045 m

## 5. 審圖

- Before／After 同鏡位（`compare/compare_*.png`，左 BEFORE＝W5B HEAD `20f8c77`，右 AFTER）：`f1_join`、`f2_upper_side`、`f3_upper_high`、`f4_top_looking_down`、`f5_close_treads`、TPS `t1_up_s85`、`t2_up_s90`、`t3_entrance_s95`、`t4_entrance_s98`、`t5_down_s100`
- **神社入口下方 TPS**：`compare_t3_entrance_s95.png`、`compare_t4_entrance_s98.png`
- 原圖 `shots/before_*`／`shots/after_*`（真實 `main.tscn` 路徑、Forward+、10:00、玩家＋SpringArm）
- 診斷（植被隱藏，僅供診斷、不是正式畫面）：`diag/z7_zoom_top_*`、`diag/abc_*`（收窄 A vs 不收窄 B）、`diag/mid_vs_top.png`

## 6. 誠實的自評與已知限制

- vision 自評約 **3／5**：與下段石材語彙的一致性、踏面完整度有改善；兩側仍有「破碎／斷續」感，石階外側的土色輪廓較 BEFORE 更顯眼。
- **最後一排（s≈98.7–99.5 m）右側約 0.5 m 的歩行幅，可見面是 P1 地形而不是石**（`cover_after.log` 的 12/17 格）：該處山坡土比踏面高 8–19 cm，A 方案（收窄）與 B 方案（全寬、被土蓋住）並排比較後選 A（較不像孤立石條）。可走性由 SWALK／行走測試確認，但這是**視覺上的取捨**，不是石已鋪滿。
- 已核准的 s≈70、83 m 側面也有類似的右端石與土坡交界（見 `diag/mid_vs_top.png`）；本段沒有比它們更差，但也沒有更好。
- 不做的事：未解凍 P1、未動相機／Auto-Step、未重做 s=37.2–89.85 的石階石垣、未動神社入口與中心線、未碰封存的 `forest_p9.scn`。
- 依「不為微小石縫反覆試作」停損：本輪共 7 輪建置比較；停止。

## 7. 檔案

新增：`godot/tools/p13/{w5c_upper_plan,build_w5c,verify_w5c_transition,walk_w5c,shot_w5c,shot_w5c_zoom,shot_w5c_hide,shot_w5c_cmpmid,shot_w5c_diag,diag_w5c_cover,diag_w5c_veg,diag_w5c_forest}.gd`
修改：`godot/maps/village_v2/gen/sando_pilot_w4_p13.scn`（只新增 `W5C` 群組）、`maps/village_v2/scripts_p13/sando_pilot_w4.gd`（`suppress_plants`）、`tools/village_v2_sando_w4_lib.gd`（`cap_l`／`cap_r`，opt-in）、`tools/p13/verify_w5b_integration.gd`（移除範圍讀 W5C END）

**STOP，等待最終 ART_APPROVAL。**
