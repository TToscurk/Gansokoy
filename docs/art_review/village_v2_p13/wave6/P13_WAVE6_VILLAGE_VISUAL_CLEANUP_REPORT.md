# P13 Wave 6 — 人間之里 道路／地形可見缺陷集中清理

> **狀態：ART_REVIEW（未 ART_APPROVED）。** 2026-10-14。基線：Wave 5C 已結案（`91a185b`）；神社石階與 P8 灌溉不重開。
> 截圖一律來自正式路徑：`main.tscn` → ReviewStart → `village_v2`、真實玩家＋SpringArm TPS、Forward+、10:00 凍結、1600×900。
> ID-pass 圖（每個像素由哪個節點畫出）只用來歸因，不當作品圖；歸因用的工具全部唯讀。

## 0. 一頁結論

| 項目 | 結論 | 處理 |
|---|---|---|
| A 道路側邊過薄的幾何面 | **不存在**：24 條道路 ribbon、7,830 三角形、薄三角形 0；P8 EarthBanks 220 件、垂直面只有 6 個三角形（0.03 m²） | 無修改 |
| A 道路與地形的暗縫 | **不存在**：邊界亮度 ÷ 兩側亮度，中位數 1.04（49 鏡位）／1.02（89 鏡位）；最暗 0.94（農道，邊界比兩側暗 6 %，W6 前後不變） | 無修改 |
| A 路面浮空／重疊 | 5 個端點 outlier（0.17–1.46 m，皆在橋頭／路端）；4 向低角度實拍未見空腔或板邊。巷道 ribbon 互疊處像素 RGB 差 ≈ 1／255（肉眼無差） | 無修改 |
| B 淡色三角形／碎片 | **根因確認：地面 overlay 的三角形內部沉到地形下面**（最深 25.6 cm），地形自己的淡灰岩層從 overlay 裡戳出來 | **已修**：`DrapeFixP13`（40 網格、194,360 三角形，只往上抬） |
| C 道路與草地的材質邊界 | **根因確認：外圍道路是等寬裸邊 ribbon**，R5a 只對 5 條套了外緣侵蝕 | **已修** 7 條：`RoadEdgeBlendP13`（套用已核准的 R5a 詞彙，不動幾何） |
| D 灰盒盤點 | 剩餘 148 棟＝187 − Wave 2 的 39 棟；其中 21 棟已在 R6a Pilot。**沒有任何可見的 P4 灰盒町家**；唯一真灰盒是丘腳社寺 | 盤點完成（§5） |

誠實限制（先講）：
- RoadEdgeBlend 的效果是「中等」：農道 3 條改善明顯，EntranceRoad／HillFoot／RiverNorth 輕微～中等，CrossStreetMid 幾乎看不出。**路面視覺上會被草色往內吃一點**（見 §4.3），這是 R5a 已核准的同一套詞彙，不是新風格。
- DrapeFix 的可見效果主要在參道／森林坡地；水車河岸 4 個機位幾乎看不出差別（§3.3）。
- **兩類更突兀的邊界我沒有動**（§4.4）：P7/P8 地形踩み固め重み造成的「V 形直邊」，以及 P8 EarthBanks 比相鄰地形亮 19 %。兩者都在封存範圍，只提案。
- 下列判讀（「改善／持平」「看不出」）是我看縮圖與放大裁切的結果，輔以數據；美術裁定是你的。

## 1. 診斷方法與證據量

| 項目 | 數量 | 說明 |
|---|---|---|
| 道路沿線 TPS 巡覽 | 49 + 89 鏡位 | 25 m／45 m 步距走遍全部道路與巷道，加 10 個疑點鏡位、8 個參道鏡位 |
| 修正後全量重拍 | 89 鏡位 | 與修前逐一同機位 |
| 針對 A/B | 10 + 4 + 4 | 道路邊界 10 機位（停用／啟用 overlay）、水車河岸 4 機位、橋頭 4 方向低角度 |
| 幾何審計（headless） | 24 道路 ribbon、54,809 標本；40 個 overlay 網格、5,442,080 標本；220 個 EarthBanks | 與 `TerrainCollision` 射線地形比對 |
| 像素歸因 | ID-pass（每像素 = 一個節點） | 邊界對、節點佔比、前後差異 |

工具：`godot/tools/p13/w6/`。**注意**：原始巡覽 PNG（約 747 MB，含 ID 圖）留在工作目錄、不入版控（體積）；入版控的是 `compare/`、`evidence/`（數據）、本報告。

## 2. TASK A — 道路表面

### 2.1 實際網格與地形高度

道路是**單層平面 ribbon**，沒有側面，所以不可能有「側邊薄板」。邊緣高出地形是設計值：

| 道路群 | ribbon 邊緣高於地形 | 備註 |
|---|---|---|
| 巷道（Lanes） | **6.0 cm**（p95 6.6 cm） | 8 條 |
| WestAlley／WestLane／主街／二次道／農道 2,3,5 | **10.0 cm**（p95 ≤ 13.1 cm） | |
| FarmPath_1／4（及 CrossStreetSouth 的 R5a 區段） | −1.5 cm（R5a 設計：與地形齊平） | 已核准 |
| 薄三角形 | **0** | 24 條共 7,830 三角形 |

### 2.2 浮空／埋入 outlier

浮空＝路面高於地形 > 15 cm 的標本。只有路的**端點**有：

| 道路 | 標本比例 | 最大 | 位置 (x, z) | 目視 |
|---|---|---|---|---|
| HillFootStreet | 0.43 % | **1.463 m** | (362.0, −131.0) | 橋頭＋護岸；**4 向低角度（7 m）未見空腔／懸空板**（`compare/A1_float_hillfoot_4views.png`） |
| RiverNorthPath | 3.41 % | 0.317 m | (380.0, −204.6) | #73 土路順坡接橋面，自然引道 |
| HillApproach（北端） | 2.47 % | 0.201 m | (281.5, −192.1) | #76 鏡位被樹葉擋住，**未能目視確認**；僅路端 1 處，未處理 |
| DragonBridgeRoad | 1.43 % | 0.169 m | (420.0, −202.5) | 橋頭 |
| WestLane／CrossStreetSouth／RiversidePath | ≤ 0.65 % | 0.155 m | — | 路端 |

埋入＝低於地形 > 1 cm：除上述 R5a 設計值外，最深 −3.2 cm（CrossStreetMid 1 處）、−2.9 cm（HillApproach 1 處），比例 ≤ 0.65 %。

**結論：沒有真的幾何錯誤。** 不下壓任何道路，不動 RoadBase。HillFoot 東端那塊「淺色矩形硬邊鋪面」是 HillFootStreet 端面＋P7 橋頭 apron（ID 歸因：道路 67 %、`RB_11_-4/-5` 6 %），屬材質邊界，不是高度錯誤（P7 封存範圍，未動）。

### 2.3 暗縫

`seam_ratio` ＝ 邊界兩側各 2 像素的平均亮度 ÷ 兩側 4–8 像素外的較暗基準（< 1 才是暗縫）。

| 鏡位集 | n | 最小 | 中位數 | 最大 | < 1.0 |
|---|---|---|---|---|---|
| 沿線（修前） | 49 | 1.00 | 1.04 | 1.48（僅 77 px） | 0 |
| 全道路（修前） | 89 | 0.94 | 1.02 | 1.18 | 6（農道 4 鏡位、WestAlley、NELane） |
| 全道路（修後） | 89 | 0.94 | 1.02 | 1.16 | 7 |

最暗 0.94 ＝ 邊界只比兩側暗 6 %。6 cm／10 cm 的路緣沒有形成肉眼可見的暗帶。

### 2.4 重疊

- **地面 overlay 與路面同高或更高**：12,657 標本，全是 P9 R5 封存的「可見最上面」規則（路口扇形踏み固め面、路肩地被）。DrapeFix 後 12,681（＋24，全在 ShrineGroveP9；最大差同為 0.196 m，位於 HillApproach 南端的埋入路端）。`compare/A2_hillapproach_south_end.png`：該處路面連續進入鳥居，無被蓋住或斷開。
- **ribbon 與 ribbon 互疊**：NE 巷道 3 條（NELane／NESouth／NENorth）在路口共面，兩次拍攝之間約 33k 像素（4 鏡位）的標籤互換（z-fight 勝負不定）。但這些像素前後 RGB 差平均只有 1.1–1.4／255（同材質同參數）→ **肉眼無差，不處理**（`road_label_swaps.txt`）。其餘 ribbon 配對都 < 250 px。

## 3. TASK B — 淡色三角形／碎片

### 3.1 根因

`Vegetation/*/Ground*` 系 overlay 只在**頂點**取地形高度再加 +1.1–1.6 cm。三角形**內部**因地形自己的三角剖分不同，會落到地形面下面（`audit_ground_before.json`）：

| overlay | 網格 | 最深沉入 | 沉入標本 |
|---|---|---|---|
| ShrineGroveP9/Ground | 1 | **25.6 cm** | 284,700 標本：0.75 % 沉 ≥ 5 mm、0.46 % ≥ 2 cm、0.19 % ≥ 5 cm |
| WatersideP9（ww1／ww2…） | 4 | 17.7／19.2 cm | |
| GroundcoverP9（Macro／Village forest／stream） | 35 | ≤ 8.8 cm | |
| 合計 | **40** | | 低於「地形＋6 mm」的標本 154,607／5,442,080 ＝ 2.84 % |

地形材質在坡面（陡）會露出**淡灰岩層**；overlay 沉下去的三角形蓋不住它，岩層就從 overlay 裡戳出來，形成淡色三角形／碎片。

### 3.2 來源排除

| 候選 | 判定 | 證據 |
|---|---|---|
| 地形 Mesh | 不是（淡色是地形自己的岩層，只在 overlay 沉下去處露出） | 同機位 `Terrain/NorthHill` 像素佔比修後 3.25 % → 1.19 % |
| RoadBase／道路 Mesh | 不是 | 薄三角 0、埋入 ≤ 3.2 cm |
| 材質權重 | 不是淡色三角形的來源（但是 §4.4(a) V 形直邊的來源） | |
| 重疊幾何 | EarthBanks 比相鄰地形亮 19 %，另成「淡色長條」（§4.4(b)） | `earthbank_share.txt` |
| **獨立環境 Overlay** | **主因** | 上表 |

### 3.3 修正：`DrapeFixP13`

只把 overlay 網格的頂點**往上**抬到「三角形內所有取樣點都不低於可見地形 +6 mm」。拓樸、UV、顏色、法線、x/z 全部不變；原 overlay 的 .scn/.res 完全不碰；以溶接頂點群處理，不產生裂縫。

| 量 | 值 |
|---|---|
| 網格 | 40（Groundcover 35、ShrineGrove 1、Waterside 4） |
| 三角形 | 194,360 |
| 實際被抬高的頂點群 | 9,755／107,843 ＝ **9.0 %**（被抬者平均 1.9 cm，最大 26.2 cm，上限 40 cm，頭打ち 0） |
| 修後 ShrineGrove 最深 | **−256 mm → +5.9 mm**（沉 ≥ 5 mm 的標本 0.75 % → 0） |
| 修後 Waterside | 最小 +5.9 mm |

![sando s=50](compare/B1_sando_s50.png)
![sando s=62/78](compare/B2_sando_s62_s78.png)

可見效果（8 個參道鏡位，`Terrain/NorthHill` 像素 ÷（NorthHill＋ShrineGrove Ground））：

| 鏡位 | 修前 | 修後 |
|---|---|---|
| s=50 | 4.3 % | 1.3 % |
| s=62 | 3.3 % | 0.2 % |
| s=78 | 1.6 % | 0.0 % |
| 8 鏡位合計 | **3.25 %** | **1.19 %** |

水車河岸（`compare/B3_waterwheel.png`，4 機位，`RiverTerrain` 佔比 5.7 % → 5.0 %）：**肉眼差異很小**；Waterside 沉入量雖達 19 cm，但這些視角被其他東西遮住。目視未見新瑕疵。

`w6_pale.py`（泛用的「比局部均值亮的離群像素」偵測器）修前後無明顯差異——它會抓到所有天然淺色（EarthBanks 亮邊、鋪面），不是這個缺陷的專用指標，**不當證據**。

## 4. TASK C — 道路與草地／裸土的材質邊界

### 4.1 根因

道路 ribbon 等寬、邊緣筆直，用 `ground.gdshader` 畫，到地形（草）之間沒有材質過渡。P10 R5a 的 `ground_p10_pilot.gdshader` 有外緣侵蝕（`edge_w` 低頻起伏、草舌、`edge_core` 草混色），但只套在 5 條：FarmPath_1／4、CrossStreetSouth、RiversidePath、HillApproach。其餘 7 條外圍道路仍是裸邊（實測 CrossStreetMid 東端：路 RGB 126,110,85 對草 81,86,58）。

### 4.2 修正：`RoadEdgeBlendP13`

把**同一個已核准的 pilot shader 與同一組詞彙**套到 7 條：CrossStreetMid、HillFootStreet、RiverNorthPath、EntranceRoad（`edge_w` 0.55）、FarmPath_2／3／5（`edge_w` 0.40、`center_patch` 0.35，同 FarmPath_1／4）。只換 `material_override`；mesh、碰撞、寬度、曲線不變。村內道路（MainStreet、巷道、橋道）**刻意不動**。

### 4.3 前後數據與取捨

道路↔地面相鄰像素對的 ΔRGB（`edge_metrics_before_after.txt`；hard ＝ ΔRGB > 25 的比例）：

| 道路 | 平均 ΔRGB 前 → 後 | hard % 前 → 後 | 目視 |
|---|---|---|---|
| FarmPath_5 | 9.1 → 6.6 | 2.9 → **0.8** | 硬直邊 → 不規則，改善明顯 |
| FarmPath_3 | 9.4 → 6.7 | 0.8 → 0.7 | 同上 |
| FarmPath_2 | 9.5 → 6.8 | 3.0 → 3.0 | 同上 |
| EntranceRoad | 7.7 → 5.0 | 4.6 → **1.9** | 輕微～中等，「直線感」仍在 |
| RiverNorthPath | 6.4 → 4.7 | 3.9 → 2.4 | 輕微改善，近景邊緣略有顆粒 |
| HillFootStreet | 4.5 → 4.1 | 1.7 → 1.4 | 邊緣打散；過渡帶偏寬、略髒 |
| CrossStreetMid | 5.5 → 4.9 | 2.7 → 2.8 | 幾乎看不出 |
| 對照：未改道路（MainStreet、巷道、CrossStreetSouth…） | ±0.1 | ±0.1 | 無變化 |
| FarmPath_1（R5a，W6 未改） | 8.7 → 8.7 | 5.3 → 5.9 | +0.6 pt：鏡位間差異量級，原因未細查 |

![farm paths](compare/C4_farmpath.png)
![entrance road](compare/C3_entrance_road.png)
![hillfoot](compare/C2_hillfoot_street.png)
![rivernorth](compare/C5_rivernorth.png)

**道路寬度**：29 個道路節點中 26 個的畫面像素修前後比 **1.000（±0.3 %）**（`road_px_before_after.txt`；NELane +17 %／NENorth −1 %／NESouth −14 % 是 §2.4 的巷道互疊標籤互換，三條都沒改）；碰撞與幾何未動。但目視上**路面被草色往內吃**——農道約 10–15 %（目視估算），EntranceRoad／HillFoot 少一點。這與 R5a 已核准的 FarmPath_1／4 同一套詞彙。若你覺得太窄，調整只需改 builder 表的 `edge_w`（0.40 → 0.30 等）重建 2 KB 的 scn。

### 4.4 沒有處理、需要你裁定的邊界（只提案）

**(a) 地形「V 形直邊」**（`compare/C6_crop_crossmid_east_1.2x.png`）：CrossStreetMid 東端／FarmPath_1 交會處前景，碎石路與淺裸土之間的銳角直邊。ID 歸因：**83 % `Terrain/FarmlandTerrain`**。是 P7 農田地形的 `COLOR.r`（踩み固め重み）2 m 格子所致——R5a 的 RoadBaseP10 已用同一技術改過 577 個頂點（416 m），這裡是還沒改的區段。
- 最小方案：沿用 RoadBaseP10 的做法（只改該地形 mesh 的 `COLOR.r`，限定在指定交會點半徑內），新 overlay；需要 R5a 的 limited reseal（明確範圍＝新增交會點）。
- 為何不做：FarmlandTerrain 屬封存地形，你規定要先授權。

**(b) P8 EarthBanks 比相鄰地形亮**（`compare/R1_earthbank_edge_block.png`）：EarthBanks 材質 `ground_k = 0.304`，相鄰 `FarmlandTerrain` ＝ `0.19`。89 鏡位中 34 個 EarthBanks 佔畫面 > 0.5 %，最多 6.6 %（FarmPath_3／4／5）；亮度比中位數 **1.19**（p10 1.10／p90 1.22）。目視像「貼在地上的淺色板子」，上緣筆直，帶一條藍灰細邊。
- 最小方案：新 overlay 在執行期複製共用材質，只調 `ground_k`（以量測對準，目標亮度比 1.00–1.05）；不動幾何／碰撞；P8 gate 需重跑。
- 為何不做：P8 封存的外觀變更（雖非灌溉）。

**(c) ribbon 端面直切**：FarmPath_1 在 CrossStreetMid 上的水平直切（ID：100 % FarmPath_1，約 140×13 px）。屬道路網格接合，需 RoadBase 重生，本輪明令禁止。

## 5. TASK D — 剩餘灰盒盤點

### 5.1 定義與總數

- 剩餘 **148 棟** ＝ 187 棟町家 Kit 建築 − Wave 2 已處理的 39 棟（`data/village_v2_p13_mainstreet.json`）。另有 9 棟 aux（納屋／土藏，Hero 管線）不屬 148、不是灰盒。
- 148 棟**全部已有 P6 Kit 幾何**（瓦、漆喰、木柱、窗格）；P4 灰盒 `Building_Main／Door／Foundation` 在 187 棟上全部 `visible=false`。**畫面上沒有「素色方塊町家」**。
- 「灰盒感」的實際來源有三：
  1. 這 148 棟仍用舊 `_matlib` 材質；R6a 已有登記的校正材質變體（18 個）並在 24 棟 Pilot 通過，**其中 21 棟屬 148**，其餘 **127 棟未校正**。
  2. 遠距顯示 Kit **LOD1／LOD2** 的簡化體（ID 歸因：神社高處看到的淺色「方塊」＝ `B_P_MXC_008/Kit/LOD1/l_box_c1_*`、`B_P_RSW_076/Kit/LOD2/l_rh_4`、`B_P_MKT_039/Kit/LOD2`）。LOD1/2 的材質是否隨 R6a 校正：**未驗證**。
  3. 屋根色重複（神社高處自評：同色藍灰切妻成排）。
- **唯一真灰盒：`LANDMARK_HILLFOOT_TEMPLE`（丘腳社寺）**。12 三角形的方塊（18×9×12 m，位置 (228, 1.2, −170)），單一素棕（RGB 0.231, 0.176, 0.134），無貼圖。

![shrine top](compare/D1_shrine_top_view.png)

### 5.2 清單

| # | 群 | 位置（中心） | 棟數（屬 148） | 已 R6a Pilot | 有正式 Kit？ | TPS 可見度 | 建議優先 |
|---|---|---|---|---|---|---|---|
| D0 | **丘腳社寺**（landmark） | (228, −170) | 1（不屬 148） | — | **無**（P5 Deferred，等你補參考圖） | HillFootStreet `c_008` 佔畫面 **10.7 %**（154,090 px）；參道起點 s=4／14 約 1.6–1.8 % | **最高；被參考圖卡住** |
| D1 | ResidentialWest | (172, −85) | 81 | 12 | P6 Kit＋R6a 校正材質 | A 68／B 11／C 2；神社高處 ≥ 500 px：18 | 1 |
| D2 | Market 周邊町家列 | (261, 13) | 29 | 6 | 同上 | A 29；神社高處 6 | 1 |
| D3 | MixedCommercial | (302, −135) | 16 | 0 | 同上 | A 15／B 1；神社高處 5 | 1–2 |
| D4 | ResidentialNE | (467, −216) | 19 | 0 | 同上 | A 14／B 3／C 2；神社高處 0 | 3 |
| D5 | SouthGate | (228, 119) | 3 | 3 | 同上 | A 3 | 已完成 |
| D6 | aux 納屋／土藏 | — | 9（不屬 148） | — | Hero 正式 | — | 無 |

可見度分級＝138 個沿線 TPS 鏡位中的最大畫面像素：A ≥ 3,000 px（路上就明顯）、B ≥ 500、C 沒看見。總計 148 棟：A 129／B 15／C 4。「神社高處」＝參道 s=60／80／96 回望南邊的 3 個鏡位。

### 5.3 後續批次建議（本輪不授權，僅排序）

| 批 | 內容 | 棟數 | 理由 |
|---|---|---|---|
| 0 | 丘腳社寺 | 1 | 全村最大的單一可見缺陷；**需要你的參考圖** |
| 1 | 127 未校正中，「≥ 3 個 TPS 鏡位下顯眼」或「神社高處 ≥ 500 px」者 | **50**（RSW 21、Market 16、MXC 8、RNE 5） | 投入／效果比最高；沿用 R6a 方法 |
| 2 | 其餘 A 級 | 61 | |
| 3 | B／C 級 | 16 | 幾乎看不到 |

批 1 開工前先查：LOD1／LOD2 材質是否同步校正。名單：`evidence/inventory_priority_batches.json`。

## 6. 對道路與地形依賴的影響

| 面向 | 影響 | 依據 |
|---|---|---|
| 碰撞（玩家／NPC／相機） | **無** | 兩個 overlay 無 CollisionObject3D／NavigationRegion3D／MultiMesh（gate I1）；開關前後場景內 CollisionObject3D 700＝700（I2）；SHRINE 實走 179 點被擋 0、WATER 56 點 0、SAN／SWALK 全過 |
| 道路寬度／曲線／高度 | 無 | 道路 mesh 不換（gate F2）；畫面像素比 1.000 |
| P1 地形 | 無 | PROTECT 0 失敗 |
| 原 overlay 資產 | 無 | 原 .scn/.res 不動；SHRINE／WATER／GC／FOREST／P9F 封存全過；`enabled=false` 完整復原（gate G1） |
| 效能 | 場景載入 ＋約 40 ms（3,264 vs 3,221 ms，暖機後）；overlay `_ready` 為 40 次網格指派 | `w6_load_time2.gd`；base 載入本身 3.2–4.1 s 是既知 P12 項目 |
| 記憶體 | 多一份 40 個網格副本（`drape_fix_p13.scn` 5.8 MB） | |

## 7. 測試結果（只跑受影響的局部檢查，未重跑整村回歸）

`tools/p13/w6/run_w6_local_checks.sh <group>`；最終狀態的全部 log 在 `evidence/gates/`（`SUMMARY.txt` 為總表）。

| 組 | 結果 |
|---|---|
| **W6 新 gate** `verify_w6_cleanup.gd` | **29 PASS／0 FAIL**（A 掛載 5、B 拓樸 4、C 溶接、D 獨立格子無沉入 2、E 完整性〔未列入 372 網格 0 件沉入〕、F 道路 4、G 往返 2、I 依存 2、H 反向 7＋正例 1） |
| 封存 `--seal` | SHRINE／WATER／GC／FOREST／P9F／RDB／EDGE／ALB／R4C／FARM：**0 失敗** |
| 場景級 | SHRINE（參道＋前庭 179 點）／SHRINE 反向／WATER（56 點）／GC／RDB／SAN／SWALK／GRD／PARCEL／PROTECT／W5B／W5C：**全 PASS** |
| 其他 | P2 水／橋 5／freeze／P4 灰盒／視線 43 站／asset reset／CANAL／P7 riverbank gate 11 項：全 PASS |
| P13 W4 pilot | PASS（1 項順序檢查已修正，見 §8） |
| **FAIL** | `TERRAIN`：`village_v2.tscn` base 載入 3,856–3,972 ms（≤ 3,000；兩次執行）——**既知 P12 項目**（P10 收尾時已記 3.5–4.3 s），W6 只增 ≈ 40 ms |

合計 39 項局部檢查：38 PASS＋1 既知 FAIL（`evidence/gates/SUMMARY.txt`）。

兩處跨層 verifier 修正（皆為 W6 追加 overlay 造成的檢查範圍問題，見 §8）。

## 8. Git 與封存狀態

- 基線 HEAD：`91a185b`（Wave 5C 最終裁定）。本輪 commit：`ce37a40`（遊戲側 overlay＋builder＋gate＋reseal＋證據＋對照圖，126 檔）與本報告的 docs commit。**本地 commit，未 push。** 原 staged 53 項與其他 session 的未提交內容未動、未納入 commit（以暫存 index 提交，完成後 staged 集合與提交前逐項相同）。
- 追蹤檔改動：`godot/maps/village_v2/village_v2.tscn` **只新增 6 行**（2 個 ext_resource＋2 個 root 直下節點）。
- 新增遊戲側：`gen/drape_fix_p13.scn`、`gen/road_edge_blend_p13.scn`、`scripts_p13/drape_fix.gd`、`scripts_p13/road_edge_blend.gd`。
- **重生 `village_v2.tscn` 後必須**：依序掛 `SandoPilotW4P13 → DrapeFixP13 → RoadEdgeBlendP13`，ext_resource id `p13w6_drape_fix`／`p13w6_road_edge`，`enabled=true`（gate A1–A5 會擋）。builder：`tools/p13/w6/build_w6_drape_fix.gd`、`build_w6_road_edge.gd`（`--dry` 與正式輸出數字完全一致＝可重現；scene 由 builder 直接生成、未經 Editor）。
- 還原：兩個節點各自 `enabled=false`（或刪節點）＝完全回到 W5C 狀態（gate G1 驗過）。

### limited reseal／verifier 修正（範圍明確）

1. **P10 R5a Road Base 封存**（`data/village_v2_p10r5a_seal.json`）：`frozen` 中**只有** `godot/tools/verify_village_v2_ground_pilot.gd` 的雜湊 1 件更新（`657453a02a9c…` → `8d0c02c8b301…`）；其餘 frozen 先逐一確認與封存時一致才寫入。`reseal_history` 新增一筆 `W6_GRD_SCENE_GATE_SCOPE_AWARE`。
   - 原因：GRD 場景 gate「非 Pilot 道路材質不變」的 scope 是封存當時的（只有 4 條 Pilot 道路變）；W6 對 7 條外圍道路套同一 pilot shader 後必 FAIL。
   - 改法：RoadEdgeBlendP13 列出的道路只要求「已換成同一 pilot shader」，其他道路仍要求材質不變；新增反向（把 MainStreet 材質換掉必須檢出 1 件）。
   - **沒改**：shader、ground_pilot.gd、ground_pilot_p10.scn、lib、RoadBase 相關、R5a plan gate、Pilot 4 道路參數。RDB `--seal` 0 失敗。
2. **P13 W4 pilot gate**（非封存，`tools/p13/verify_w4_pilot.gd`）：「SandoPilotW4P13 是 root 的最後一個子節點」改為「自己之後只有 `…P13` overlay」（意圖＝晚於既有 overlay 才蓋得過，仍被檢查）。

### 登記的已知缺陷（承 W5C，未動）

- 石階最後約 0.5 m 右側步行幅不是完整石鋪面、部分邊石／笠石收尾破碎、石階與土坡局部突兀。
- ForestP9 2 株植物僅在 `SandoPilotW4P13` 啟用時隱藏。

## 9. 待你裁定

1. **RoadEdgeBlend 路面內吃**：維持（與 R5a 同詞彙），或把 `edge_w` 調小（農道 0.40 → 0.30；EntranceRoad／HillFoot 0.55 → 0.40）？
2. **§4.4(a) V 形直邊**：授權沿用 RoadBaseP10 技術局部改 FarmlandTerrain `COLOR.r`（需 R5a limited reseal）？
3. **§4.4(b) EarthBanks +19 %**：授權用 overlay 對準亮度（P8 外觀變更，P8 gate 重跑）？
4. **丘腳社寺**：何時補參考圖？（唯一真灰盒、全村最大單一缺陷）
5. **R6a 擴張批 1（50 棟）**：是否開工（含先查 LOD1／LOD2 材質）？

## 10. 檔案索引

- 對照圖：`compare/`（A1 橋頭 4 向、A2 丘裾路端、B1／B2 參道、B3 水車、C2–C8 道路、D1 神社高處、R1 EarthBanks）
- 數據：`evidence/`（`audit_roads_before.json`、`audit_ground_*.json`、`audit_banks.json`、`audit_overlap.json`、`drape_fix_report.json`、`edge_metrics_before_after.txt`、`road_px_before_after.txt`、`road_label_swaps.txt`、`earthbank_share.txt`、`survey*_boundary.log`、`inventory_*.json`、`bld_vis_*.json`、`inventory_remaining148.json`、`inventory_priority_batches.json`）
- gate：`godot/tools/p13/w6/verify_w6_cleanup.gd`；一鍵：`bash godot/tools/p13/w6/run_w6_local_checks.sh {seals|scenes|roads|p13|wide|all}`
