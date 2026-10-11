# P12 FINAL CLOSURE 補充報告（2026-10-12）

狀態：三項已處理，送驗收（STOP）。只跑了受影響的檢查：沒有完整回歸、沒有實走、沒有效能量測。

## TASK 1 — HUX 015／016（實物修正，已完成）
- 同一個生成器、同一個 seed 局部重烘（`HUX_ALLOW_REBAKE=1`）。snapshot 只有這兩件不同：
  - `015_mk_tsumini` (337.15, 0.219, 47.15) → **(337.40, 0.218, 47.15)**
  - `016_hu_seoikago` (338.70, 0.211, 47.95) → **(338.95, 0.210, 47.95)**
  - X +0.25 m；Y 因重新貼地 −0.001 m。其餘 38 件、朝向、who/why、說明資料與 snapshot 頂層欄位全部不變。
- 015 與 T0 支線可見網格的最短距離：0.339 → **0.571 m**（≥ P8 禁區 0.4 m）。這個數字是頂點對頂點量的。正式判定以 HUX plan gate 的 P8 禁區檢查為準，結果 PASS。
- r3 審圖基準 `plan_r3.json` 不改。R4b seal 新增 `approved_position_overrides`，**剛好 2 筆**，記錄 node、r3 原位置與核准位置。checker 內也寫死同一組值，seal 的內容必須與 checker 一致，否則拒絕。其他 38 件仍用 r3 的 2 cm 容許值。
- 新增 5 個反向案例，全部正確失敗：
  - 核准件再移動 0.25 m。
  - 例外 key 加到這 2 件以外的道具。
  - 合法 key 的核准座標被改寫。
  - 刪除其中 1 筆例外。
  - 不套例外時，這 2 件會與 r3 不一致（證明例外確實有作用）。
- 檢查：HUX `--seal`／plan／`--negatives`／`--scene` 全部 0 失敗。

## TASK 2 — P9 蘆葦封存差異（登記，不重新生成）
- 來源：P11 R2C 局部重烘河岸 RB_11_-7。只把這一區換回舊版，plan gate 就通過。
- 現場：封存的 202 件 `wk_*` 節點以 `_blocked()` 檢查，侵入通路 0 件（只讀 probe：植物取半徑 0.4 m、其他只取中心點，未用正式 gate 的 `prop_corners()`，屬輔助證據）。被規劃判定擋路的那株，實物 `Plants/120_wk_reed_s` 在 (328.75, −45.25)，不在通路上。WATER `--scene` 實走膠囊 56 點，被擋 0 點。
- `verify_village_v2_waterside.gd` 新增 `P12_DRIFT`。以下全部一致時，才容認這 1 件規劃障害：
  - 障害集合剛好是 `wk_reed_s@(329.7,-47.2)`。
  - 上游 RB_11_-7 lod0/lod1 的雜湊。
  - 封存 `waterside_p9.scn` 的雜湊。
  - 整份規劃的摘要。
  - 實物位置，且以同一判定仍在通路外。
- 反向案例：分別竄改上游雜湊、overlay 雜湊、規劃摘要、實物位置，或多加 1 個障害，都會讓例外失效。
- 檢查：WATER plan／`--negatives`／`--scene`／`--seal` 全部 0 失敗。

## TASK 3 — P9 草地封存差異（登記，不重新生成）
- **數字更正**：目前用正式 ENV 前處理重算的規劃株數是 **114574**，不是 117045。117045 來自先前的隔離實驗，那次換入的 `farmland_p8.scn` 其實是 Git LFS pointer，不是真的檔案，所以該值作廢，只當歷史紀錄。
- 來源：P11 R2D 農田水利（`farmland_p8.scn`）改變了草地規劃的避障輸入。換回 R2D 前的實檔，ENV 就通過。
- 現場：封存的 `meadow_p9.scn` 保持不動，全部 LOD 共 153,772 個 instance（封存近級 114,105＋中級 39,667）。在支線範圍 x 320–370、z −55–85（涵蓋完整支線，bounds 326–364／−45–78）內：
  - 落在支線土渠外寬內：0。
  - 落在道路面上：0。
- `verify_village_v2_environment.gd` 新增 `P12_MEADOW_DRIFT`。以下全部一致時才容認：
  - 封存近級 114105。
  - 目前株數 114574。
  - **株位摘要雜湊**（同數量但位置不同的漂移也會被擋下）。
  - 上游 `farmland_p8.scn` 雜湊。
  - 封存 `meadow_p9.scn` 雜湊。
- 「固い物の足元に草 0」檢查保持原樣。
- 反向案例：株數 +1、株位摘要不同、上游雜湊被改、meadow 雜湊被改，例外都會失效。
- 檢查：ENV plan／`--negatives`／`--seal` 全部 0 失敗。

## 封存
- Limited reseal：
  - `p9r44`／`p9r54` 只更新 verifier 的雜湊。
  - `p10r4b` 更新 overlay、snapshot、verifier 的雜湊，並寫入核准例外。
- 子封存連動只更新雜湊：P9 FINAL、P10 R3b／R3c／R3d／R3e／R4／R4b。每份都記 `reseal_history`。
- 全部 seal 的 frozen／child／sub 雜湊比對：不一致 **0**。
- `--seal` 檢查 0 失敗：WATER、ENV、P9F、HUX、HUSE、POP、ACT、CORE、OUTER。

## 已接受、但仍未通過的效能偏差（不宣稱 PASS）
- 地形檔載入 > 3000 ms：Districts 優化延到 P13 建築改造之後再評估。
- P8 高視角 +4.03–4.09 ms：上限仍是 4.00 ms，標記為已接受偏差。

## Git
- 本輪 commit 只含明確列出的檔案；不 push。
- 原本 staged 的 53 項未變（逐行比對一致）。
- 他 session 的 `main.gd`、`yoriichi_character.gd` 雜湊未變。

## 審查
這個環境無法啟動獨立的 GPT agent。中途參考的 GPT 意見指出兩個缺口，已補上：例外座標原本可被任意改寫，草地只比數量擋不住位置漂移。但沒有人對最終 diff 做過獨立 ACCEPT。
