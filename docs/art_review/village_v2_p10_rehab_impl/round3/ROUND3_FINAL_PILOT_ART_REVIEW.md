# P10 R5–R6 ROUND 3 — FINAL PILOT ART_REVIEW

狀態：**ART_REVIEW（未 ART_APPROVED、未封存、未 reseal 任何受影響階段）**。依 ROUND 3 停止條件，本輪結束後 STOP。
未做：水車 1／3、第二艘船、全村建築重做、NPC 擴張、Human-Use 擴張、main.gd、player 相機程式。未 push；使用者 staged 53 項未動（每次 commit 前後 staged 53→53）。

## 1. 總覽

| 工作包 | 本輪做了什麼 | 主要視角自評（vision） | 技術 gate |
|---|---|---|---|
| R5b 水車 2 | 撤除揚水部材 → 純動力下掛け水車；流向＝受力方向；P8 高架落とし樋 runtime 隱藏（Pilot override） | 西 3／東 3／高 3 | WLF plan 0 失敗・反向 9/9、scene 0 失敗 |
| R6b 參道 | 三平台保留；新 walkable-surface gate SWALK；ARM_PULL 根因診斷；局部石材老化 | 下行 3／平台往下 2／往上 2 | SAN 0 失敗・反向 8/8；SWALK 0 失敗・反向 5/5 |
| R5a Road Base | A–D 切分診斷 → 根因＝P7 地形 trodden 頂點權重；局部修正 Pilot | 6 m 4／8 m 4／10 m 4／高 4 | RDB plan 0 失敗・反向 7/7、scene 0 失敗 |
| R6a Kit 材質 | 方案 A：Kit 專用校正材質 18＋變體登記表＋合法變體 gate KITM；24 棟改用登記材質 | 與核准 24 棟同值（逐屬性差 0、像素差 ≤ 1.39/255） | KITM 0 失敗・反向 6/6；ALB 0 失敗 |

各包細節與 remaining issue：`r5b_water/README.md`、`r6b_shrine/README.md`、`r5a_road/README.md`、`r6a_kit_material/README.md`。

## 2. Waterwheel 2（東、西、高視角 BEFORE／ROUND 2／ROUND 3）
`r5b_water/panels/wlf2_ww2_west_tps_tri.jpg`、`wlf2_ww2_east_tps_tri.jpg`、`wlf_ww2_east_tri.jpg`、`wlf_ww2_high_tri.jpg`（另 8 m、樋）。
- 揚水部材 0；輪下端移動 · 水渠下流＝1.000；葉板浸水 0.35 m；主泡在出水側。水車 1／3 不動。
- 不再宣稱揚水到 3.30 m：P8 高架段（`Chute_0/1`、`ChuteJoint`、`HeadBearer`、`Support_00/01`；碰撞 `Post_00/01`、`Chute_1`）runtime 隱藏，P8 檔案不變。
- **Remaining**：P8 的取水鏈（落とし桝以下）失去水源而看起來斷開（東視角）；水渠水位 −1.52 vs 田面 0.20，本地無法自流。P8 limited correction 選項與受影響封存檔列在 `r5b_water/README.md` §Remaining 1（需授權）。
  `p8_tone` 與隱藏都是 Pilot override，正式版必須改成 P8 limited correction＋reseal。

## 3. Shrine（上行、下行、平台實走；ARM_PULL）
- 實走影片（正式 main.tscn F5 路徑，pitch 固定 −0.18）：`r6b_shrine/walk/seg2_steps_up_2x.mp4`、`seg3_steps_down_2x.mp4`、`seg1_end_vista_2x.mp4`。
- **ARM_PULL 比較**：
| | 實走下行事件 | 診斷：拉近比例 | 診斷：次數 |
|---|---|---|---|
| ROUND 1（一本斜坡） | 1（使用者報告值） | 73 % | 2 |
| ROUND 2（踊り場 3） | 5 | 55 % | 5 |
| ROUND 3（同碰撞＋老化） | 4 | 55 % | 5 |
| 參考：pitch −0.35 | — | 5 % | 1 |
- **根因**：30° 坡 vs 預設 pitch −0.18（腕只抬 10°）。只有地形時也 73 % 被拉近 → 不是階梯 Mesh（相機入石 0）、不是斜坡碰撞特有；
  1→5 是平台讓一段長拉近被切成數段（拉近總比例反而 73→55 %）。未關閉相機碰撞；相機轉接器的「陡坡下行 pitch 偏置」只提案（需授權）。
- 第一次 ROUND 3 實走起動時 pitch 被滑鼠事件改成 +0.338（條件不同）→ 作廢；`walk_p10_final.gd` 新增 `--pitch=`。
- **SWALK**（P9 R4-2 scope-aware／walkable-surface verifier correction 的提案實作；舊 gate 不動）：W1 可行走面位置、W2 玩家膠囊淨空、W3 平台上下高度連續、W4 平台邊緣與兩側、W5 NPC 巡回、W6 正式 TPS 相機、W7 與 P9 R4-2 同路線——全 PASS，反向 5/5（含「相機碰撞關閉」必失敗）。
- **Remaining**：TPS 距離下老化細節讀不出（2–3/5），石段仍像程序化模組。替代：CC0 掃描石段 kit／曲率 AO 磨損 shader／鼻先不規則化（`r6b_shrine/README.md` §5）。

## 4. Road Base（近距與高視角；P7 道路殘影根因證據）
- 根因證據：`r5a_road/band_diag/*_sheet.jpg`＋`band_diag.json`（A RoadBase OFF／B 隱藏道路 Mesh／C 地形 road weights 歸零／D 權重可視化／E 隱藏地被）。
  B 仍有舊路寬直帶、C 消失、D＝trodden（G）→ **P7 FarmlandTerrain 頂點權重**（gen `_road_halo`、2 m 格子內插）。不是 Road Mesh、地被或 shader 條件。
- 修正（P7 limited correction 的 Pilot，runtime）：只改 577 個頂點的 COLOR.r，位置／UV／索引不變，封存檔 sha256 不變，enabled=false 還原。
  B→C 色差：farmpath4 6.75→0.67、cross_south 7.98→2.47、高視角 2.61→1.45（`band_diag_after/`）。
- 近距／高視角三聯：`r5a_road/panels/grd_farmpath4_6m_tri.jpg`、`grd_cross_south_edge_8m_tri.jpg`、`r5a_farmpath1_n_tri.jpg`、`r5a_farm_road_high_tri.jpg`。
- **Remaining**：土／草交界局部偏硬；未再生的其他田間小路仍是直帶（範圍外）。

## 5. R6a Kit Material Pilot
- `godot/assets/village_v2/machiya_kit_cal/`：校正 4＋調色盤 14＋`kit_material_variants.json`（登記表）；AlbedoPilotP10 外部參照登記材質。
- 三聯（ROUND 1 核准 r5｜ROUND 3）：`r6a_kit_material/panels/*.jpg`；`pixel_diff_vs_round1.json`。
- KITM：override 只在登記的 Pilot 24 棟、全是登記變體、與基底只差 albedo（atlas 只差 k）、_matlib／P6 Kit 原檔 git 未變；其餘 163 棟 0。Kit Gate 未改。

## 6. Gate、效能、封存衝突
- 全量回歸 132 項：**121 PASS／11 FAIL**——Pre-existing 4、Expected Pilot Seal Conflict 6（ROUND 3 新增 P8 FEEDER）、Newly Introduced 1（P9 R4-2，ROUND 2 起）。詳見 `regression/CLASSIFICATION.md`。
- 效能（GTX 1070、1600×900、Forward+；同機位 A/B 交互 2 對，`perf/`）：
  - 本輪改動 4 overlay（Albedo／WaterLife／ShrineApproach／RoadBase）開關差：−0.14〜+0.15 ms（`perf_round3_changed4_toggle.json`）。
  - 全 7 overlay 開關差與 ROUND 2 一致（±0.1 ms 內）；全開最高＝參道石段機位 14.36 ms（第一輪 14.27、ROUND 2 14.10），持續追蹤。
  - 第一次 changed4 量測時 GPU 被同時進行的 git commit 壓縮佔用（全部機位 off 值約 2 倍）→ 標示 `_CONTENDED_invalid` 保留不採用；all7 檔的 `perf_arrival` 一列同樣受影響（off 23.30），不採用。
- 封存衝突與 ART_APPROVED 後的 reseal 清單（未執行）：
  1. P6 Kit Gate：「無 override」→「只允許登記變體」（更嚴格白名單）＋P6 limited reseal。
  2. R4 HUSE／R4b HUX：A2 1 件＋st_hasa_v2 參照的 limited reseal。
  3. P9 R4-2：以 SWALK 的最上面可行走面做 limited verifier correction＋reseal。
  4. P8：落とし樋高架段撤除＋灌溉來源（需先選方案）＋`p8_tone` 改為材質規範 → P8 limited correction＋reseal；FEEDER 依新形狀更新。
  5. P7：FarmlandTerrain COLOR.r 修正進 gen（或封存檔重烘）＋P7 reseal。
  6. P5 白名單：登錄 `machiya_kit_cal`（19 檔）。
  每項須保留前後雜湊、原因、依存、反向測試。

## 7. Remaining issue 一覽（STOP 時點）
| 項目 | 分數 | 剩餘問題 | 可行替代方案 |
|---|---|---|---|
| 水車 2 | 3/5 | 入水與流向的視覺提示弱；P8 灌溉鏈失去水源 | P8 limited correction（上游自流／踏車／溜池三選一）；入水白波加強 |
| 參道 | 2–3/5 | 程序方塊石的模組感；平台往下看前景大石板 | 掃描石段 kit／磨損 shader／鼻先不規則化 |
| ARM_PULL | — | 下行 4–5 次（根因在相機 pitch vs 坡度） | 相機轉接器陡坡 pitch 偏置（模擬 5 → 1 次，需授權） |
| Road Base | 4/5 | 交界偏硬；範圍外小路仍直 | 路肩過渡列／全村擴張（需授權） |
| R6a | 同核准值 | 187 棟未套用 | 取得新亮度基準後另案 |
