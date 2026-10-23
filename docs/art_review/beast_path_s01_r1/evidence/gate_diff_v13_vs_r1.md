# Gate 改版前後差異（V1.3 final → S01 R1）

- V1.3 final：66 項（PASS 60／INFO 6／FAIL 0）
- R1 verify_r1_final（與先前的 verify_r1c 逐項判定相同；只有 s01.lean_semantics 的說明文字修正過——先前把已是度的設定值又換算了一次，顯示成 229.2°）：74 項（PASS 68／INFO 6／FAIL 0）

## 被移除的 Gate：0


## 新增的 Gate：8

- [PASS] `isolation.protected_files`：V1.3 基準 279 個檔逐位元相同（不同 0：[]）；場景檔 raw 相同 3、只差 unique_id ["beast_path.tscn"]、不同 []；S04 共用 shader／材質（bp_ground／bp_rock）未動 true
- [PASS] `isolation.layout_other_zones`：layout 對 V1.3：S02／S03／S04 與全域設定改動 []；非 S01 的 POI 改動 []、新增在 S01 之外 []、順序相同 true；新增鍵 ["s01_ground"]／["s01_candidate"]（只允許 s01_ground、s01_candidate）；S01 的 POI 有變 5 筆、新增 0 筆
- [PASS] `isolation.s01_terrain_locked`：S01 地形碰撞檔 s01_terrain_shape.res 與 V1.3 逐位元相同 true；S01 地形網格的頂點位置＋法線＋索引雜湊與 V1.3 相同 true（本輪只動地表著色，不動高度與碰撞）
- [PASS] `s01.candidate_declared`：S01 候選 mode＝r1、round＝R1-a；現行凍結區 ["S02", "S03"]；forest_plan.json 的 S01 380 筆
- [PASS] `s01.candidate_reproducible`：S01 候選（380 筆）以相同輸入與 seed 規劃兩次：不同 0 筆（要求 0）；與 forest_plan.json 逐筆比對不同 0 筆（要求 0）；規劃輸入 已讀到 357 個道具腳印
- [PASS] `s01.scene_equals_plan`：S01 場景裡 380 棵植被的 transform 與候選規劃不同 0 棵；最大數值差 0.000004
- [PASS] `s01.lean_semantics`：微傾的樹 42 棵：傾向／傾角與規劃不符 0 棵（要求 0）；傾向最大差 0.00000、傾角最大差 0.00000 rad；最大傾角 229.2°
- [PASS] `s01.count_budget`：S01 植被 380 筆（V0.1 基準 380；允許 361–418＝−5 %…+10 %，超過要先提理由）：{ "tree": 308, "pin": 8, "under": 64, "dead": 0, "bamboo": 0 }

## 同名 Gate、判定內容有變：5

### `nodes.static_bodies`  （ok True → True）
- 舊：StaticBody3D 共 2201 個
- 新：StaticBody3D 共 2182 個

### `forest.freeze_file`  （ok True → True）
- 舊：凍結檔 forest_plan_v01_s01_s03.json：雜湊吻合 true、凍結 2776 筆（S01 380／S02 1213／S03 1183；V0.1 為 380／1213／1183）
- 新：凍結檔 forest_plan_v01_s01_s03.json：雜湊吻合 true；歷史基準 2776 筆（S01 380／S02 1213／S03 1183；V0.1 為 380／1213／1183）；現行凍結區 ["S02", "S03"] 共 2396 筆（要求 2396）；S01 已宣告候選規劃 true

### `forest.frozen_plan_equal`  （ok True → True）
- 舊：forest_plan.json 的 S01–S03 共 2776 筆，與凍結檔（V0.1）逐筆比對不同 0 筆
- 新：forest_plan.json 的 ["S02", "S03"] 共 2396 筆，與凍結檔（V0.1）逐筆比對不同 0 筆

### `forest.frozen_scene_equal`  （ok True → True）
- 舊：S01–S03 場景裡 2776 棵植被的 transform 與凍結檔（V0.1 場景存檔值）不同 0 棵；最大數值差 0.000015
- 新：["S02", "S03"] 場景裡 2396 棵植被的 transform 與凍結檔（V0.1 場景存檔值）不同 0 棵；最大數值差 0.000015

### `forest.zone_independent`  （ok True → True）
- 舊：不靠凍結檔、只改 S04 規則：S01–S03 共 2828 筆植被改變 0 筆（要求 0）；S04 814→874 筆（對照組：必須有變）
- 新：不靠凍結檔、只改 S04 規則：S01–S03 共 2884 筆植被改變 0 筆（要求 0）；S04 927→888 筆（對照組：必須有變）

## 完全相同的 Gate：58 項（判準、結果、數字一字不差）

---

## 附註：`forest.zone_independent` 的對照數字為什麼變了（已量測，非推測）

判定式 `leak == 0 && s4_changed` 沒有改、結果仍 PASS；只有 INFO 文字裡的筆數不同：

| 解凍模式（`set_freeze(false)`）下的 S01 登記表 | S01 | S02 | S03 | S04 一般 → 擾動 |
|---|---|---|---|---|
| V1.3 舊規則（候選 OFF，現行程式碼路徑）| 404 | 1259 | 1165 | **814 → 874**（＝V1.3 final 的數字，一字不差）|
| `replay`：V0.1 凍結檔的 S01 原樣 380 筆 | 380 | 1331 | 1208 | 841 → 893 |
| `r1`：本輪候選 380 筆 | 380 | 1380 | 1124 | 927 → 888 |

結論：
1. 候選 OFF 時與 V1.3 **逐數字相同** → 我沒有改動舊規劃路徑。
2. 連 `replay` 都會讓「解凍後」的 S02／S03／S04 重新規劃結果改變 → 這是舊規劃器的固有性質：各區依序擲點、共用樹距註冊表，S01 登記的樹只要有一棵不同，邊界附近的接受／拒絕就變，後續亂數的消耗序列整段位移。**不是 R1 才有的耦合。**
3. 對實際輸出沒有影響：live 模式下 S02／S03 由凍結檔逐筆載入、S04 由 V1.2 凍結檔載入，`forest.frozen_plan_equal`／`frozen_scene_equal`／`s04` 相關 Gate 與 `forest_plan.json` 逐筆比對（S01 之外 3602−380＝3222 筆 0 筆不同）都證明了。
4. 對將來的影響：若哪天要把 S02／S03 解凍重排，必須先處理這個「S01 變動連動後續區」的性質（例如給每區獨立的註冊表快照），本輪不碰。
