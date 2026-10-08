# P10 FINAL — Integrated Village Walkthrough／ART_REVIEW（2026-10-08）

**狀態：ART_REVIEW（Read-Only Review）。** 本輪沒有修改任何場景、封存資產、地形、植被、道路、NPC 或 Human-Use 物件；只新增審查用工具與證據。是否結束 P10 由使用者裁定。

## 一、走訪方法（實際遊戲）
- **正式 F5 路徑**：`scenes/main.tscn` → `scripts/main.gd` → `ReviewStart`（`--review=kirisame`）→ 載入 `village_v2`；既有 TPS 相機（`Player/CameraAdapter`：SpringArm 8.5 m、pitch −0.18、rotation_smoothing 26）、10:00 凍結、Forward+、視窗 1600×900、HUD 隱藏（同 main.gd 的 `"hud": false`）。
- **連續實走，無瞬移**：從 review spawn（霧雨店前 237.1, 71.7）**走**到南大鳥居外，然後依 8 段道路一路走完：`move_forward`（＝W 鍵）＋視線朝向下一路點（`CameraAdapter._target_yaw`，等同滑鼠轉向，保留相機平滑）；方向差 > 50° 時先轉身再走；卡住時左右橫移。步速 4.0 m/s（中位數）。
- 路線＝`maps/village_v2/layout_v2.json` 的道路中心線＋市集 `mouth／lanes`、市集西 `FLOOR／LANES`（`tools/walk_p10_final_route.json`）。事前點檢（`--precheck`，玩家膠囊 r 0.3）0 問題段（`gate/route_precheck.log`）。
- **結果**：實走 **1,127 m**（＋準備段 56 m）、340 s；**STUCK 0／BLOCKED 0／TIMEOUT 0／對話打斷 0**；606 個 0.5 s 樣本全部接地；ARM_PULL（SpringArm 縮到 < 55 %）7 次（見 §五：其中 3 次畫面被擋／入地，2 次輕微，2 次正常）。
- 工具：`godot/tools/walk_p10_final.gd`（走訪／`--precheck`／`--grid`）、`tools/sheet_p10_final.py`（審圖シート）。

## 二、交付
| 類別 | 檔案 |
|---|---|
| TPS 截圖 12 張（1600×900、正常 TPS） | `stills/S01_south_gate.png` … `S12_forest_edge.png`；總表 `review/stills_all.jpg`、放大 `review/stills_{1,2,3}.jpg` |
| 走訪錄影 8 段（960×540、2 倍速 mp4） | `walk/seg1_gate_main_2x.mp4` … `seg8_forest_edge_2x.mp4` |
| 每段 12 コマ | `review/seg_<段>.jpg` |
| 相機事件 | `review/armpull.jpg`（7 次 ARM_PULL 的前／中／後）、`review/camera_check.jpg` |
| 紀錄 | `gate/walk_log.json`（樣本・事件・still・各段 fps）、`gate/walk_stdout.log`、`gate/full_regression.log` |

## 三、評分（1–5，NPC ON 實際遊戲；判定依 TPS 截圖＋各段 12 コマ＋走訪紀錄）
| 區 | 分 | 依據 |
|---|---|---|
| 1 南入口（大鳥居）→ 主街南段 | **2** | 建築與 R2 店頭外溢都在，但大鳥居〜中橫街約 125 m **NPC 0**（最近 NPC 中位 44 m；S01 25 m 內 0 人、S02 0 人）。畫面上第一次看得到人在 36.7 s（往市集口方向）。 |
| 2 主街北段 → 市集南口 | 3.5 | 大幟「市」・提灯・人流漸增，過渡自然；口內相機被屋簷遮擋（§五 C2）。 |
| 3 市集廣場 | 4 | 全村最熱鬧（S04 25 m 內 28 人），攤位・商品可讀；人物以站位為主、交易互動不明顯；前景棚頂偶爾遮擋。 |
| 4 Market West | 4 | 最像持續營業的商店街（S05 25 m 內 17 人）；市集 → 連絡道 → 通り 的過渡連續；野點傘・提灯在前景遮擋。 |
| 5 住宅後巷（西巷 → MidLane → R4 B） | 3 | 安靜但不死（終點有井戸端・住民）；從 MidLane 看 R4 B 的後院像大空地，生活物件在巷道距離偏小。 |
| 6 Bridge_03 → 農田 | 3.5 | 村 → 田的過渡漸進（稲架・藁塚・荷車在橋前後就讀得到）；田中央安靜（意圖）；從道路看區畫偏圖式（P8 封存）。 |
| 7 水車／水渠 | 4 | 「有在用、但不忙」：洗濯・修理・住民在村側岸，對岸與水路其餘段落保留自然留白。 |
| 8 神社參道 | 4 | 由市街 → 草地 → 鳥居 → 參道的安靜轉換明確；左側 丘腳社寺 灰盒很醒目（D1）。 |
| 9 村邊 → 森林方向 | 3.5 | 丘腳街・NWLane 安靜、留白適當（不需補道具）；NWLane 末端又聚成住宅群，沒有明確「出村入林」；丘腳社寺灰盒；參道腳相機入地（C1）。 |

**整體：3.5／5。**
核心問題「是否像一座長期有人生活的村莊，而不是數個獨立場景拼起來」：**大致是一座村。** 建築語言、地面、植被、P8／P9／P10 各層在走訪中沒有風格斷層，密度由核心（市集・市集西）向外（後巷 → 水岸 → 農田 → 神社 → 森林邊）遞減，且外圍留白讀起來是刻意的安靜，不是未完成。**最明顯的拼接感只有一處**：南入口 → 主街南段「有店卻無人」，人群在市集口才一起出現——玩家從獸道入口進村的前 30 秒看到的是空街。

## 四、問題清單
### BLOCKER（提案，需使用者裁定）
- **B1 主街南段無人流**：南大鳥居（234, 100）〜中橫街（262, −20）約 125 m 的主街，R2 店頭外溢（13 種商い）完整，但 51 人中**沒有一人站在這段**（R3d「主街 10 人」全部在 z −11〜−45 的市集口一帶；C6 巡回的南端 z −11.5）。這是玩家從 `PORTAL_TRAIL` 進村的預設路線，直接對應本輪驗收項「主街的人流」。
  - **最小修正方案（不增 NPC、不增物件、不改構圖）**：R3d limited reopen——把主街北段已成對聚集的 3–4 人（例：S2／S3 (265, −42)、C13／C14 (262, −32)）移到主街南段的店前（霧雨店前・火見櫓前・南橫街の辻），或把既有巡回 S4／C6 的路線往南延長；沿用已封存的 Activity 語彙；總數 51・核心 39 不變。之後 R3d reseal，並連帶更新以 R3d 為子封存的 R3e／R4／R4b 雜湊。
  - 若你判定這是刻意的密度梯度（入口安靜、市集熱鬧），可降為 NON-BLOCKING。

### NON-BLOCKING（可接受，不再微調）
- **N1** 市集・Market West 的 NPC 以「站位＋待機」為主，買賣交談等互動在 TPS 距離不易讀（R3c 封存的語彙範圍）。
- **N2** 狹窄通道上有 NPC 站位：市集南口 M2（247.3, −33.6）、市集 → Market West 連絡道 C10（232.0, −49.9）——實走可繞過（0 stuck），但通道變窄。
- **N3** 住宅後巷：從 MidLane 看，R4 B 的後院呈大片空地、生活物件偏小（與 R4 已核准時的「B 側面 3/5」同根）。
- **N4** 農田：從農道看，田區整齊偏圖式；農田人口稀疏（R3e 外圍設計）。
- **N5** NWLane 往森林方向的末端仍是住宅群，「出村入林」的終點感不強；留白本身適當，不需補道具。
- **N6** 市集前景的條紋棚頂、Market West 的野點傘，在部分轉角會占掉畫面一角（構圖，非穿模）。

### DEFERRED（後續階段）
- **D1（P5 Hero，待參考圖）** 丘腳社寺 `Landmarks/LANDMARK_HILLFOOT_TEMPLE`＝P4 灰盒 BoxMesh（12 三角面、`placeholder`），在神社參道（S11 左側）與丘腳街（seg8）都很醒目，是目前最大的「未完成」破綻。
- **D2（P13 lighting）** 主街南側北向店列、後巷、市集棚下 10:00 偏暗。
- **D3（P12 performance）** 走訪中 fps 中位 24–37、最低 8（錄影每 0.1 s 同步讀取畫面，僅供參考）；P8 runtime budget 見 §六。
- **D4（P12 load time）** terrain gate 的「base 載入 ≤ 3000 ms」：本次 4270 ms（P9 R2 時 2697 ms）。gate 只把 forest／bamboo 當 overlay 扣除，其後所有 overlay（P9 R4–R5、P10 Props・人口・Activity・R4／R4b）都計入 base。不放寬 gate。
- **D5（KNOWN_SCOPE_DEBT）** P5 asset reset：違規 398 → 421（場景依賴 1795 → 1824；P10 新封存 Kit／NPC 依賴進入場景），白名單不擴張（既有裁定）。

## 五、相機（單獨記錄，本輪不改相機）
| # | 位置 | 現象 | 嚴重度 |
|---|---|---|---|
| C1 | 參道鳥居腳（289.5, −167.7），轉身下參道時 | SpringArm 4.4 m，相機**進入山坡地形約 0.9 s**，畫面是地形背面＋天空（`review/camera_check.jpg` seg8 f0／f3／f8） | 最嚴重；同「SpringArm 穿屋頂」一類（相機碰撞 vs 可見幾何），建議與既知問題一起在相機任務處理 |
| C2 | 市集南口（246.6, −35.6） | 2.66 m，屋簷・樑占滿畫面上方，玩家只露腳 | 短暫 |
| C3 | MidLane 轉角（248.9, −84.7） | 3.69 m，牆擋住左半邊與玩家 | 短暫 |
| C4 | 主街 × 中橫街の辻（seg2 開頭，約 260, −16） | 相機落在店前下屋的柱・樑後方，玩家暫時看不見（未觸發 ARM_PULL：SpringArm 沒有縮短） | 短暫 |
| C5 | Market West 連絡道（232.5, −46.5） | 1.63 m，遠 → 近 → 遠的拉伸 | 輕微 |
| C6 | MidLane 東端 × 主街（280.9, −85.9） | 4.55 m，前景的柱擋住玩家一部分 | 輕微 |
| — | 其餘 2 次 ARM_PULL（西巷入口 200.8, −44.5；中橫街 263.8, −23.0） | 一般的轉角拉近，畫面正常 | 無 |
- 既知：Market West 的 SpringArm 穿屋頂（獨立 tech debt）。

## 六、技術整合（全專案回歸）
`godot/tools/run_village_v2_regression.sh` 全 116 項（`gate/full_regression.log`，5219 s）：**112 PASS／4 FAIL**。對照基準＝2026-10-07 R3b 全回歸 94/96（`village_v2_p10_population/pilot_r1/evidence/full_regression_final.log`）。

| FAIL | 分類 | 內容 |
|---|---|---|
| P5 asset reset gate | **既有**（KNOWN_SCOPE_DEBT） | 違規 398 → 421（場景依賴 1795 → 1824）；P5 白名單不涵蓋後期封存 Kit／NPC，既有裁定「不擴白名單」。 |
| P8 runtime budget（五鏡位 A/B） | **既有**（PRELIMINARY／UNRESOLVED） | High_overlook GPU Δ +4.08 ms（上限 4；前次 +4.09）；P12。 |
| terrain gate（base 載入 ≤ 3000 ms） | **新回歸（性能）** | 全回歸中 4270 ms；機器閒置・溫快取再量 3560／3526 ms（P9 R2 時 2697 ms）。10-07 之後掛上的 5 個 overlay（R3d 核心・入口 cue・R3e 外圍・R4・R4b）單獨載入合計僅 226／241 ms；其餘是更早累積（P9 R4–R5、P10 R1–R3b 都算進 base）＋環境敏感（冷快取一次 17.3 s）。terrain gate 其餘 62 項全 PASS（地形・坡度・道路・橋端等）。分類 **DEFERRED P12（load time）**，不放寬 gate（`gate/load_time_breakdown.txt`）。 |
| P9 R4-3 寺子屋周邊 scene gate | **新回歸（跨層）** | 「入口＋前庭＋南側院＋北側通路」膠囊實走 145 點中 2 點被 **R3d 的巡回 NPC C20_kozo_m01** 擋住（205.4, 24.2／204.9, 24.2）。C20 的巡回線 (202.0, 20.4)→(205.0, 24.0)→(206.4, 25.6) 橫過寺子屋前庭。P9 gate 只排除地形，寫於人口層之前；R3d 當時的回歸子集沒有跑這支 scene gate，所以沒被抓到。遊戲上＝小孩在寬廣前庭來回走，玩家可繞過（本次走訪路線未經過寺子屋）。 |

- 其餘 112 項（含 R1／R1b／R2／R3b–R3e／R4／R4b 全部封存、P8／P9 全封存、MMBAKE、擺放稽核）PASS。
- **新回歸 2 的最小修正方案（需使用者同意，本輪未改）**：
  - (a) **驗證器 scope 修正**（建議）：P9 R4-3 scene 的膠囊實走只量靜態內容，排除 `Population/**` 的 NPC body（動態角色由 R3b–R3e 自己的 gate 檢查）；另加一條「idle NPC 不得站在入口軸上」以保留原意。→ P9 R4-3 limited reseal（`verify_village_v2_school_yard.gd`）＋P9 FINAL seal 與以它為子封存的 R4／R4b 雜湊更新。NPC 配置不動。
  - (b) R3d limited reopen：把 C20 的巡回線往南偏 1–1.5 m，不橫過前庭的入口線。→ R3d reseal＋R3e／R4／R4b 子封存雜湊更新。會改到已核准的 NPC 配置。

## 七、結論
- **P10 的主體已經形成一座村**：從南入口走到森林邊、1.1 km 連續實走沒有卡住、沒有風格斷層；核心（市集 4・市集西 4）熱鬧、水岸（4）與神社參道（4）在使用感與安靜之間的平衡是對的，外圍留白讀起來是刻意的。
- **唯一影響體驗的拼接點是 B1（主街南段無人）**——它恰好在玩家進村的預設路線上，對應本輪驗收項「主街的人流」。
- **建議**：**條件式 ART_APPROVED**——
  1. B1：若你判定為刻意的密度梯度 → 可直接核准；若不是 → 先做 B1 的最小修正（R3d limited reopen，移 3–4 人或延長既有巡回，總數 51 不變），再核准。
  2. 兩個新回歸都不是美術問題：terrain load time 歸 P12；寺子屋 scene gate 的跨層衝突建議以 (a) 驗證器 scope 修正處理（需你同意 reopen P9 R4-3 的驗證器）。
  3. 相機 C1（參道腳入地）與既知的 Market West 穿屋頂一起，單獨開相機任務處理，不屬於 P10 內容。
- 本輪未修改任何封存內容、場景、相機；停在 ART_REVIEW，等待正式裁定。
