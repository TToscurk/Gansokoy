# P11 R2C — Limited Geometry & Irrigation Corrections（2026-10-11）

狀態：送驗收（STOP）。視覺部分只到 ART_REVIEW。

## A. 浮空道路 — DONE（範圍比授權更小）

- **最後只改 4 條路、67 個頂點**，不是授權的 7 條／76 點。第一次套用 76 點後，P7 河岸 gate 出現 3 件橋頭鋪石浮 0.10 m（RBG grounding FAIL），P9 Macro m9 地面 sha 也變了。原因是其中 9 個頂點其實站在**橋面**上（橋頭），以地形為基準往下壓，等於把橋頭路面壓到橋面底下。改用「頂點正下方第一個地形或橋面」當支撐面重算後，HillFootStreet、DragonBridgeRoad、WestLane 這 3 條路沒有任何頂點真正浮空，所以不改。
  - HillApproach 1、RiverNorthPath 19、CrossStreetMid 8、RiversidePath 39。
  - 修正後：三角形內部最大浮起 0.217 m（RiverNorthPath 一處接橋頭）、其餘 ≤ 0.155 m；最大橫坡 26°（HillApproach 原有坡）；回讀頂點數／surface 一致；法線只在動到的三角形重算。
- **河岸（P7）**：記憶體重排後與場景逐區塊比對，65 區塊中只有 `RB_11_-7` 改變（43→52 件，碰撞 shape 不變）。只覆寫這一區塊的 LOD0／LOD1 mesh，以及 `village_v2.tscn` 裡 Riverbank／RB_11_-7 的 meta（2766→2775 件、LOD0 628,654 ≤ 650k）。
- **地被（P9 R5）**：規劃與 m9 ground digest **不變**，GC plan gate 0 失敗，**不需要 reseal**。
- **封存**：沒有任何 seal 檔列入這些 mesh；全部封存雜湊比對 0 不符。這輪沒有做 reseal。
- **殘留**：路面本來就設計比地形高 +0.10 m（全村共同，R2B 前就是如此）。從 0.25 m 高的低視角看，路緣仍有一條薄邊，不再有懸空的整片路面。TPS 視角看不出浮邊。這條 +0.10 薄邊屬於 P13 polish，不在本輪範圍。

## B. 水車 1／3 — 調查完成，**重力供水（從水渠）不可行**，提出一個方案待裁定（未施工）

| | 水車 1 → N0 | 水車 3 → T0 |
|---|---|---|
| 水渠水面（水車旁） | −1.397 | −1.521 |
| 田區進水口要求水面（槽底＋0.05） | 0.168 | 0.368 |
| **必要揚程** | **1.57 m** | **1.89 m** |
| 現有高架樋頭 | 3.42 | 3.30 |
| 150 m 內更高的真實水面 | 無（唯一命中是 WATERFALL_F7 的 placeholder 方塊頂 0.69，不是水面） | 同左 |

結論：水渠在兩塊田的下方 1.6–1.9 m，現有地形無法讓水自然流進去。只降低高架樋只能改外觀，水仍然上不去。

**最小可行方案（一個，待裁定）**：不新增揚水機，**沿用水車 2 已有的竜骨車系統**，從它的出口分出低位地面木槽，往南北各接一條：
- N0：落とし桝 水面 0.28 → N0 進水口 0.168，長 51.8 m，水頭 0.112 m（坡度 0.22 %）。沿線地面 41 點中有 5 點高於「水面 −0.10」，靠近落とし桝的一段需要淺挖或把槽架在矮枕木上。
- T0：送り樋 水面約 0.55 → T0 進水口 0.368，長 73.5 m，水頭 0.182 m（0.25 %）。有 2 點地面太高（約 0.42）。路線會穿過 CrossStreetSouth 一帶，要用暗渠或跨路板。
- 接著撤除 Feeder_N0／T0 的高架樋、支柱、ChuteJoint、HeadBearer；保留各自的落とし桝與地面木槽。
- 修改範圍：P8 `village_v2_farmland_zone.gd` 的 feeder 生成，加上 FarmlandP8 重烘（非 headless），P8 limited reseal，FEEDER gate 加入水位鏈檢查與「高架樋殘骸 0」。
- 風險：一台人力竜骨車要供應 3 個田區，這在水量上是否合理需要美術／設定判斷；坡度 0.22–0.25 % 偏緩但屬於可行範圍。
- 替代：保留現狀，高架樋整個交給 P13。

## 測試（只跑受影響項目）

- 道路：`drape_roads_r2c.gd --check／--apply`（頂點、三角形內部、坡度、橋頭、回讀）
- P7 河岸 gate `--regress` 0 失敗（含 grounding、烘焙＝重排 2775）
- P9 R5 GC plan gate 0 失敗（m9 ground 不變）
- P10 R6b 參道 SAN 0 失敗（參道用 HillApproach ribbon 計算 cut_s）
- P3 parcels gate 0 失敗
- 沒有跑 143 項完整回歸，也沒有跑全村實走。
- 畫面 `shots/`：
  - **低視角 Before／After（同鏡位）**：`before_*.png`（R2B 開工前、未改任何道路時拍的 `shot_road_layers.gd` 原圖）對 `after_*_samecam.png`（R2C 最終版，同一個腳本、同一組鏡位），共 5 處：riverside、rivernorth、crossmid、hillfoot、main_side。
  - **TPS 只有 After**：`after_*_tps.png`、`after_*_low.png`。原本打算拍的 TPS Before 作廢：拍攝時用 `git checkout` 切回舊檔，但因 `.git/index.lock` 失敗，拍到的其實是修改後的場景，所以刪除不提交。沒有用切換共享工作樹的方式補拍。

## Git

- 一個本地 commit，未 push；原 staged 53 項以 `git diff --cached --raw`（含 blob ID）比對，結果不變。
- `main.gd`、角色控制器、相機檔案都沒有動。
