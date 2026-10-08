# P10 R5–R6 Environmental Rehabilitation — IMPLEMENTATION ART_REVIEW

**狀態：ART_REVIEW（第一輪 Pilot），未 ART_APPROVED、未封存、未重新封存任何受影響階段。**
使用者 2026-10-09「P10 R5–R6 MASTER AUDIT — 10 Decisions Approved」＋施工指令 v3.0。HEAD 起點 `d0f870e`（MASTER AUDIT）。

## 0. 一頁結論

| Step | 工作包 | 狀態 | Agent 自評（vision，**不是 ART 判定**） | 技術 gate |
|---|---|---|---|---|
| 1 | **R5c 邊界收邊**（D2） | 實作完成 | 東緣 TPS 4、北稜 TPS 4、村高視角 4 | plan 11＋反向 4/4、scene 6、視線射線 25,852 條看見盡頭 0、VOID_EXIT 0 |
| 2 | **R6a 亮度基準＋街區調色盤**（D8，Pilot 24 棟） | Pilot 完成 | 南大鳥居→主街 4、入口高視角 4、西巷住宅 4 | plan 9＋反向 9/9、scene 8 |
| 3 | **R5a 田格外溢＋道路外緣**（D4 limited；D3 base 重生未做） | Pilot 完成 | 田區高視角 4、農道 TPS 4、近距 6 m 3 | plan 8＋反向 7/7、scene 7 |
| 4 | **R5b 水車 2 揚水化＋主河小舟 1**（D5、D10） | Pilot 完成（3 輪停） | 水車 東 3／高 3／**西側 8 m 2**；舟 TPS 3／12 m 3／河面 3 | plan 7＋反向 6/6、scene 9 |
| 5 | **R6b 一の鳥居端景＋參道石段（斜坡碰撞）**（D6、D7） | Pilot 完成（3 輪停＋r3b 技術修正） | 主街端景 4、一の鳥居 4、參道中段 TPS 4、石段腳 3、側高 3、**往下看 2** | plan 9＋反向 6/6、scene 6、實走上下 0 阻塞、NPC 巡回 6 條干涉 0、19-point walk 0.05 m |
| 6 | **R6a 建築差異** | 併入 Step 2（同一 overlay、同一 Pilot 範圍） | 同上 | 調色盤反向 2/2 |
| 7 | **R4c 稲架穿插＋A2**（D9） | 完成（r1b 接地修正） | 稲架近距 4、10 m 4、A2 4 | plan 8＋反向 5/5、scene 7 |
| 8 | **河船**（D10） | 併入 Step 4 | 同上 | 同上 |

**順序調整**：R6a「建築差異」與「亮度基準」共用同一個 overlay 與 Pilot 範圍，所以在 Step 2 一起做；河船與水車共用水系 overlay，所以在 Step 4 一起做。沒有突破授權範圍。

**全部改動都是 overlay／新資產**：唯一被修改的既有檔＝`village_v2.tscn`（純新增 18 行＝6 個 overlay 的掛載）、回歸總表（＋12 行）、2 個審圖工具。沒有任何封存檔、P1 地形、P3 道路檔、P5／P7／P8／P9 資產被改；任何 Pilot 都可用 `enabled=false`（材質覆寫類）或移除掛載行還原。

## 1. 各階段完成／未完成

### Step 1 — R5c World Edge Closure（`r5c/README.md`）
- 完成：frame 外 Vista 地形（接縫 ≤ 0.01 m）、水系延續（主河東／北出口、南水渠、西溪 → 南の川 → RiverEast，水位單調）、近帶實樹 2,312 棵＋遠山林冠；**碰撞 0**、P1 地形與 Collision/Boundary 4 牆不動。
- 掉落與視覺裁切分開驗證：實機 15 邊界點跑＋連跳全 PASS；BFS 可達 74,691 格、VOID_EXIT 0；視線閉合射線 25,852 條看見世界盡頭 0。
- 未完成／阻礙：**V2→他圖 portal 落點 fallback (0,40,0)** 在 `main.gd`（D1 HOLD，他 session 未提交 +376 行），本輪不動。
- 殘留：林帶間距略規則、遠山林冠平滑（vision 指出「略像一道牆」）。

### Step 2＋6 — R6a 材質亮度基準＋建築差異（`r6a_albedo/README.md`）
- 根因：`_matlib` 建物 albedo_k 0.42（Compatibility 時代係數）→ 日照下白漆喰 luma 0.431 < 18 % 灰卡 0.647。
- 完成：Pilot 24／187 棟（A 入口〜主街南段、B 西巷住宅）漆喰 0.70／木 0.75／基石 0.65、**瓦不校正**；町家 Kit atlas 用等價 shader 依色階分類（屋根灰不提亮，LOD 切換不跳亮度）；街區調色盤（A 商業暖白＋飴色／紅殼／素木、B 住宅灰土色＋風化灰／煤色木），飽和 ≤ 0.22、14 m 內鄰棟不同組。
- 未做：全村套用（需 ART_APPROVED 後改 `_matlib`＋Kit atlas → P7／P6 limited reseal）；牆面汚し（雨垂れ・泥はね）。
- 殘留：前景漆喰略白、Pilot 內外反差（Pilot 本質）、牆面仍乾淨均一。

### Step 3 — R5a 道路與田格（`r5a_ground/README.md`）
- 根因：P7 `ground.gdshader` 在 farm 權重 > 0 處程序畫 24×16 m 田格 → P8 田外／路下的第二套田格；道路＝等寬直邊 ribbon。
- 完成（D4 limited fix）：封存 shader 雜湊驗證後做 6 段文字補丁 → pilot shader（田格段移除、外緣侵蝕＋草舌＋切口內混草、田埂道中央草帶斷續）；Terrain 4 段＋Pilot 道路 4 條執行期換材質。外緣沿路標準差 0.12–0.22 m（核准 0.08–0.45）。
- **未做：D3 base 重生**（外緣用 shader 解；局部浮邊 丘腳街橋頭 1.46 m／河岸小徑 0.59 m 仍在）。全面套用＝補丁併入 texture builder → 重生 `ground.gdshader` → `_matlib` limited reseal（依 D4，需 ART_APPROVED）。
- 殘留：侵蝕邊略塊狀、路面內部均一、近距 6 m 草侵入有遮罩感。

### Step 4 — R5b 水車／水道／主河（`r5b_water/README.md`）
- 水系拓撲：主河取水口 → 水渠 −1.13→−1.63 單調南流；P8 田面比水渠高 1.4–1.9 m → 田必須揚水。
- 三座功能定義（**不是 all-pump**）：水車 2＝揚水（**本輪實作**）、水車 3＝揚水（建議，未動）、水車 1＝動力（精米／搗き，建議，未動——需精米小屋＋P8 取水改線＝要裁定）。
- 水車 2：柄杓 16（輪東面、與輪同轉）＋輪頂受け樋（接 P8 落とし樋頭 Δy 0.014 m）＋原本懸空的 3.30 m 樋頭下補 2 柱架台。P5 水車與 P8 樋原檔不動。
- 主河：P7 唯一親水石段下端 1 艘川舟（7.2 × 1.5 m、吃水 0.12、船首迎流、俵 3、吃水線白波）＋繫船杭＋舫い綱＋石段頂「届いた荷」。第二艘依 D10 待審。
- 殘留：柄杓只能放在輪東面 0.18 m 間隙 → **西側 8 m 機位 2/5**（被輪輻遮住）；小舟從岸上 TPS 被 P7 岸緣遮掉大半，卸貨感弱。下一輪選項見 README。

### Step 5 — R6b 神社參道／端景（`r6b_shrine/README.md`）
- 完成：一の鳥居（P5 `sando_torii` 重用）立在參道 s 7 m，主街第 5 段軸心盡頭的端景；**MXC_018 不動**。石段 186 段＋石疊 2（蹴上 0.131–0.191、踏面 0.25–0.45、寬 3.0＋袖石），碰撞＝平順斜坡（與踏面差 ≤ 0.114 m、最大 37.3°）；石燈籠 3 對（坂に据えた水平基壇）。
- 通行測試：**玩家**（正式 main.tscn、真實輸入、既有 TPS 相機）上行 69.5 m、下行 90 m 0 阻塞；**相機** ARM_PULL 1 次（SpringArm 縮 4.65 m，非穿模）；**NPC** 初期位置＋巡回 6 條與石段／鳥居柱干涉 0（人口與路線不搬）。
- r3b 技術修正：19-point walk 斜線乗り上げ一の鳥居柱台（dy 0.50）→ overlay 柱台ガード（r 0.52、資產不變）→ 0.05 m PASS。
- 殘留：往下看 2/5——遠段明暗差小（偏藍 sky ambient＝P13 debt）、袖石逐段鋸齒；燈籠基壇坂下露高面。下一輪選項：連續斜袖石、踊り場（燈籠立在踊り場）、踏面前緣面取り。

### Step 7 — R4c 稲架（`r4c_props/README.md`）
- 完成：新資產 `st_hasa_v2`（封存 street_kit 不動），竿×半束 0.016 m、束頭坐竿 0.001 m（接觸不穿）、束×束 0.011 m、脚×束 0.063 m；全村 9 處換 mesh（位置／件數不動）；A2 背負い籠東移 1.0 m（視線距 0.07 → 0.86 m），只動這一件。
- 封存：R2／R4／R4b **不重封**（D9：ART_APPROVED 後才併入 street_kit 並 reseal）。
- r1b 技術修正：全回歸發現 A2 籠沈在地下 1.0 m（gate 射線打到籠自身碰撞）→ 地面＝TerrainCollision、反向 N5 追加；重拍後 A2 4/5。
- 殘留：束頭偏方、稲穂質感；千歯扱き齒在 TPS 距離讀不清。

## 2. BEFORE／AFTER 截圖
同機位、10:00、Forward+、1600×900、乾淨渲染（無 LANDMARK 標籤／網格／Gizmo）；`*_b.png`＝overlay OFF（BEFORE）、`*_a.png`＝AFTER、`pairs/*_pair.jpg`＝左右並排。

| 工作包 | 目錄 | 機位 |
|---|---|---|
| R5c | `r5c/`（15） | TPS 11（東田區、河口、北稜、西稜、南水渠、南入口、神社外望、到站、南橫街軸）＋高視角 4 |
| R6a | `r6a_albedo/`（9） | TPS 6 m／12 m／14 m 立面、南大鳥居、入口、西巷 2＋高視角 2 |
| R5a | `r5a_ground/`（9） | 町→田、農道 2、水岸、南橫街東端、近距 6 m／8 m＋高視角 2 |
| R5b | `r5b_water/`（8） | 水車 8 m／東／樋頭＋高；舟 TPS／12 m／河面＋高 |
| R6b | `r6b_shrine/`（8＋實走） | 主街端景 2、一の鳥居 10 m、參道腳／中段／石段 5 m／往下看＋側高；`walk/` 錄影 3 段＋still 5 |
| R4c | `r4c_props/`（6） | 稲架 A1 近距／10 m／遠、XA3、FarmEdge、A2 脫穀作業床 |

## 3. 修改的 Scene／Mesh／Material／Shader／Script

| 類別 | 檔案 |
|---|---|
| 掛載（唯一改動的既有場景） | `godot/maps/village_v2/village_v2.tscn`：root 末尾依序 `EdgeClosureP10 → AlbedoPilotP10 → GroundPilotP10 → WaterLifeP10 → ShrineApproachP10 → PropFixP10`（＋18 行，0 刪改；sha256 前 `8830bab4…` → 後 `7decaaad…`） |
| overlay 場景 | `maps/village_v2/gen/{edge_closure,albedo_pilot,ground_pilot,water_life,shrine_approach,prop_fix}_p10.scn` |
| overlay 執行期腳本 | `maps/village_v2/scripts_p10/{albedo_pilot,ground_pilot,water_life,shrine_approach,prop_fix}.gd` |
| Shader | `maps/village_v2/shaders_p10/ground_p10_pilot.gdshader`（封存 ground.gdshader 的補丁產物）、`kit_cal_p10.gdshader`（Kit atlas 等價） |
| Mesh／新資產 | `assets/blender/village_v2/build_hasa_v2.py` → `assets/village_v2/r4c_kit/src/r4c_kit.glb` → `maps/village_v2/gen/r4c/st_hasa_v2(_l1).res`；水車柄杓／受け樋／架台、川舟、石段、斜坡碰撞、燈籠基壇＝generator 程序網格（在各 overlay 內） |
| 生成器／gate | `tools/village_v2_{edge_closure,albedo_pilot,ground_pilot,water_life,shrine_approach}_lib.gd`、`tools/verify_village_v2_{edge_closure,albedo_pilot,ground_pilot,water_life,shrine_approach,prop_fix}.gd`（tag EDGE／ALB／GRD／WLF／SAN／R4C，已併入回歸總表） |
| 工具 | `perf_village_v2_rehab.gd`（多節點 ON/OFF）、`shot_village_v2_rehab_audit.gd`（enabled 切換）、`walk_p10_final.gd`（`--route=`，預設不變）、`probe_village_v2_rehab_albedo_cal.gd` |
| 重用的既有資產（未改） | P5 `sando_torii`、garden_kit `gk_toro_kasuga`、street_kit `st_kago_tsumi`、P9 veg_kit、`_matlib` V2_Wood／V2_Stone（duplicate 後調色） |

## 4. 封存完整性
- 封存檔改動 **0**：`git diff --diff-filter=MDR d0f870e..HEAD` 只有 `village_v2.tscn`（純新增掛載）、回歸總表、2 個審圖工具。
- 依賴：AlbedoPilot／GroundPilot 在執行期讀 `_matlib`／machiya_kit／ground.gdshader 並驗證來源雜湊（GRD：ground.gdshader＝matlib.json 封存值）；PropFix 讀 street_kit 的 st_hasa 只換 mesh 參照；SAN 讀 P3 參道 ribbon 只覆寫 shader 參數；WLF 讀 P5 水車轉子只掛子節點。
- 封存 `--seal`：見 §6 回歸（15 項全跑）。R2／R4／R4b／P7／P8 seal **未重封**；ART_APPROVED 前不重封。
- 人口 51、NPC 身分／位置／動畫、R4 原 50 件、R4b A/B 40 件：未改（POP／CORE／OUTER／HUSE／HUX `--seal` 驗證）；R4b 被拒的 C 未恢復。

## 5. 效能（同機位 ON／OFF ABAB 各 2 對取中位數，GTX 1070、1600×900、Forward+）
`perf/perf_r5r6_pilots5_toggle.json`（5 個新 Pilot）、`perf/perf_r5r6_all6_toggle.json`（含 R5c 全 6 個）。

| 機位 | 5 Pilot OFF GPU ms | ON | ΔGPU | Δdraw | 全 6 overlay OFF | ΔGPU | Δdraw |
|---|---|---|---|---|---|---|---|
| `perf_alb_gate_n` | 9.18 | 9.31 | +0.13 | +49 | 8.77 | +0.59 | +100 |
| `perf_alb_west_alley` | 9.37 | 9.39 | +0.02 | +13 | 8.57 | +0.86 | +132 |
| `perf_arrival` | 13.46 | 13.56 | +0.09 | +55 | 13.17 | +0.48 | +78 |
| `perf_east_edge_high` | 8.36 | 8.44 | +0.08 | +0 | 5.17 | +3.31 | +147 |
| `perf_east_edge_tps` | 9.04 | 9.11 | +0.07 | +0 | 6.58 | +2.52 | +153 |
| `perf_grd_farm_road_high` | 11.38 | 11.50 | +0.12 | +34 | 11.32 | +0.24 | +50 |
| `perf_main_street` | 8.63 | 8.78 | +0.15 | +32 | 8.16 | +0.63 | +97 |
| `perf_north_ridge_out` | 9.71 | 9.74 | +0.03 | +0 | 5.30 | +4.46 | +181 |
| `perf_r4c_hasa` | 8.29 | 8.72 | +0.43 | +2 | 7.63 | +1.10 | +94 |
| `perf_san_steps` | 13.92 | 14.21 | +0.29 | +2 | 12.78 | +1.49 | +155 |
| `perf_sando_foot` | 11.17 | 11.19 | +0.02 | +7 | 10.28 | +0.94 | +130 |
| `perf_village_high` | 12.00 | 12.13 | +0.13 | +68 | 10.96 | +1.21 | +102 |
| `perf_west_ridge_out` | 10.90 | 10.94 | +0.04 | +0 | 5.32 | +5.63 | +227 |
| `perf_wlf_boat` | 8.54 | 8.66 | +0.13 | +7 | 6.82 | +1.83 | +148 |
| `perf_wlf_ww2` | 8.74 | 8.89 | +0.14 | +10 | 7.83 | +1.04 | +106 |

- 5 個新 Pilot：ΔGPU **+0.02～+0.43 ms**（最大＝稲架機位 +0.43、石段 +0.29），Δdraw ≤ +68。
- 含 R5c 全 6 個：村內 +0.2～+1.8 ms；朝外看邊界的機位 +2.5～+5.6 ms（原本外面是空的所以便宜）；**ON 後最高絕對值 14.27 ms（石段機位）**，仍在既有村中心機位的範圍內。未見 catastrophic 項目。

## 6. 回歸
全量 `run_village_v2_regression.sh` 128 項（`regression/full_regression.log`，修正前）：**118 PASS／10 FAIL**。
- **既知、與 P10 FINAL 相同（未惡化）4 項**：TERRAIN 場景載入 3.84 s（> 3.0 s，P12；P10 FINAL 4.27 s）、P5 ASSET 白名單違規 421（件數不變；本輪新增依存 15 件全在白名單內）、P8 COST High_overlook +4.01 ms（P10 FINAL +4.08）、P9 R4-3 寺子屋 scene（R3d C20 巡回擋 2 點，同一訊息）。
- **本輪造成、已修正 2 項**：
  - 19-point walk（最大 |玩家y−地面| 0.50 m）：斜めの歩行線が一の鳥居の柱台（P5 碰撞 0.72 角・高 0.58 m）に乗り上げ → overlay 側に柱台ガード追加（資產不變）→ **0.05 m PASS**。
  - HUSE 接地「最大の埋まり 1.002 m」：A2 背負い籠が 1.0 m 沈んでいた（r1 gate の射線が籠自身の碰撞に當たった）→ 地面＝TerrainCollision に修正、反向 N5 追加 → 接地 −0.002 m。
- **Pilot の設計上の偏差（D8／D9 授權；ART_APPROVED 後の全面套用／reseal で解消）5 項**——修正後の影響範圍再跑 `regression/rerun_affected_after_fix.log`（12 項：7 PASS／5 FAIL＝下記のみ）：
  - P6 KIT：AlbedoPilotP10 が Pilot 24 棟の表面に執行期 override（P6「無 override」規則）
  - R4 HUSE scene：PropFixP10 が R4 の st_hasa を v2 mesh（`gen/r4c/`、kit 外パス）に差替
  - R4 HUSE seal／R4b HUX scene・seal：A2 背負い籠 1 件の移位（D9「A2 只調必要位置」）＝R4 snapshot 不一致 1 件だけ
  - **封じ込め確認** `regression/proof_pilots_off.log`：AlbedoPilotP10／PropFixP10 を `enabled=false` にすると上記 6 run 全部 PASS（0 失敗、他の不一致なし）。確認後 `village_v2.tscn` を HEAD に復元（sha256 `7decaaad…` 一致、git diff 0）。
- 封存 `--seal`：P8／P9 R1–R5・FINAL／P10 R1・R1b・R2・R3b・R3c・R3d・R3e・NPCLIB 全 PASS；R4／R4b は上記 A2 移位のみ（不重封、D9）。
- MMBAKE（全 MultiMesh 零矩陣 0）、PLACE（場景擺放稽核＋永久反向）、RBG、STR 等その他 PASS。

## 6b. 擺放驗證的範圍（godot-asset-placement-validation）
- 場景級 PLACE 稽核（`audit_village_v2_placement.gd --selftest`，Landmarks Hero／灰盒／橋）：PASS＋永久反向 5 案照預期——**新物件不在它的覆蓋範圍內**（一の鳥居在 ShrineApproachP10 下、不在 `Landmarks/`）。
- 新物件改由各自的 gate 驗：一の鳥居 柱台＋ガード vs 既有碰撞／道路（SAN 6）、石段 188 段 vs 地形（不被蓋、斜坡碰撞差 ≤ 0.114）、燈籠 6 基＋基壇（四角接地、不撞）、
  架台 2 柱（落地水渠底 −0.30 埋入）、小舟（浮力／不壓石段／水深）、繫船杭（埋 0.35）、荷（四角起伏 0.07）、A2 籠（移位後接地 −0.002、碰撞 0）、st_hasa_v2（外形＝原 AABB，原擺放不動）。
- 實機：19-point walk、參道上下實走、R4 HUSE 擺放（3×3 ray＋collide_shape）＝封じ込め確認で PASS。**以上是「目前稽核範圍內」未發現擺放問題**；R5c 的 2,312 棵樹與 Vista 地形由 EDGE gate（水中／陡坡／接縫）驗證，不在 PLACE 單元內。

## 7. Git（scoped、未 push、使用者 staged 53 項未動）
| commit | 內容 |
|---|---|
| `f542dc6` | Step 1 R5c Edge Closure |
| `bc34dca` | Step 2＋6 R6a 亮度基準＋街區調色盤 |
| `8e1cafd` | Step 3 R5a Ground Pilot |
| `97c416f` | Step 4 R5b 水車 2＋小舟 |
| `2f3253c` | Step 5 R6b 參道石段＋一の鳥居 |
| `ca1f7d7` | Step 7 R4c 稲架 v2＋A2 |
| `2f617cd` | 全回歸で発覚した 2 件の修正（R4c A2 接地／R6b 柱台ガード）＋gate 強化 |
| （本報告） | 效能、回歸、報告、規劃 §37、.hermes.md 狀態 |

每個 commit 用一時 index 建立，前後 `git diff --cached` 都＝同一組 53 項。

## 8. 需要使用者裁定／明確 blocker
1. **main.gd HOLD（D1）**：portal fallback (0,40,0) 未修；需確認 +376 行的所有權與協調方式。
2. **D3 base 重生**：未做；若要根治浮邊需重生 `gen/road_*.res`（最小作用域、先快照、驗 P3 依賴）——請確認是否進下一輪。
3. **水車 1／3**：功能定義已提案（3＝揚水、1＝動力精米），水車 1 需精米小屋＋P8 取水改線（P8 reopen）——需裁定；精米小屋未自動新增。
4. **各 Pilot 全面套用**（ART_APPROVED 後）：R6a → `_matlib`／Kit atlas（P7／P6 limited reseal）；R5a → ground.gdshader（P7 `_matlib` limited reseal）；R4c → street_kit 併入（R2／R4／R4b reseal）。
5. **第二艘船**：依 D10 待本 Pilot 審過再送審。
6. 停止規則已到：R5b、R6b 各 3 輪，未達 4/5 的機位（水車西側、石段往下看、舟 TPS）列在各 README「殘留＋下一輪選項」，**沒有用加道具去補**。

**STOP — 等待 ART_APPROVED／裁定。**
