# P10 R5b.1 Irrigation Source Reconstruction — 實作（ART_REVIEW，未 ART_APPROVED）

使用者 2026-10-10 P10 FINAL CLOSEOUT：「R5b.1 灌溉：方案 B LIMITED APPROVAL」——允許 P8 limited correction；以一台竜骨車優先；
正式移除失去功能的架高落とし樋、無效支柱及相關碰撞；保留水車 2 純動力；修正 FEEDER 指出的實際場景問題；只改必要的 P8 內容與下游依賴並記錄 limited reseal history；
不做兩段踏車、不加第二座提水水車、不重做農田或河流、水車 1／3 不動。

## 結論
- **單台竜骨車可以合理供水**，沒有改用替代方案。
- 必要揚程 **1.81 m**：水渠水面 −1.52 m 到落とし桝水面 0.288 m。
- 實際設計揚程 **2.18 m**：從水面算到吐き口（樋底上端 0.66 m）。
- 竜骨車傾斜 **28.4°**，樋長 **5.17 m**。
- 竜骨車之後全程依高程自流，水位逐段下降、沒有任何一段倒流：

  水渠 −1.52 →（竜骨車）吐き口 0.66 → 送り樋 0.59→0.56 → 落とし桝 0.288 → 上段土渠 0.278 → 伏越し 0.27／0.19 → 木槽 0.18→0.15 → 內渠 0.078

## 位置（實測選定，`tools/survey_village_v2_irrigation.gd`＋臨時格點搜尋，已刪）
- 設在水車 2 下游的東岸，取水口在 (331.0, 4.85)。
- 水車 2 的旋轉圓盤 AABB 範圍是 z ≤ 3.81，取水口離它 1.0 m 以上。
- 取水口與地形、水面：
  - 渠底 −2.33 m，取水口樋底在渠底上方 0.49 m。
  - 取水口樋底在水面下 0.28 m。
  - 下車下緣 −1.75 m。
- 樋在岸坡（P7 石積み）上方通過：
  - 樋底板下面到地面最少 0.18 m（x 335.1）。
  - 沒有立中間架台。原本有中間架台，但它的腳會穿進 P7 的 RB_10_0 護岸石（12 個頂點），所以撤掉，改成兩端支撐：下車用杭，上車用門形架。
- 頭部門形架位在岸頂 (335.46, 3.85–5.85)。
- 送り樋 (335.40→338.62) 架在 0.20 階面上：
  - 樋底下面到地面 0.24 m。
  - 末端伸出到落とし桝上方，下面 0.46 m，高過桝壁頂 0.45 m。

## 改動（P8 limited correction）
| 檔案 | 內容 |
|---|---|
| `tools/village_v2_farmland_lib.gd` | 新增竜骨車常數（`RYU_*`／`FEED*`）、`ryu_basis()`、`ryu_axle()`；`supply_posts()` 改為竜骨車的柱。<br>`_supply_body` 撤去高架樋碰撞（`Post_00`／`Post_01`／`Chute_1`），換成竜骨車碰撞：柱 8、`RyuHead`（拐木旋轉範圍）、`RyuRail`、`RyuTrough`、`Feed`。<br>`CHUTE` 常數只保留作記錄。 |
| `tools/village_v2_farmland_visual.gd` | `_supply_art` 撤去 `Chute_0`／`Chute_1`／`ChuteJoint`／`HeadBearer`／`Support_00`／`Support_01`，新增 `_ryukotsu_art`，包含：<br>傾斜樋、羽根板鏈（汲水側＋回程側）、上下車、踏み軸＋拐木 4 輪、門形架＋手摺＋方杖、杭、送り樋＋妻板＋腳＋落水。<br>`rng` 消耗順序不變，所以其他構件逐一相同。 |
| `maps/village_v2/gen/farmland_p8.scn` | 非 headless 重新 build（MultiMesh 規則）。 |
| `data/village_v2_p8_seal.json` | 只更新 frozen 的 3 件，新增 `reseal_history` 一筆（kind `R5B1_IRRIGATION_SOURCE_RYUKOTSU`），P8 status 不變。 |

**下游依賴（未封存的 R5b）**：WaterLifeP10 改成**不碰 P8 任何節點**，ROUND 3 的 runtime 非表示／碰撞停止已撤除。涉及檔案：
- `village_v2_water_life_lib.gd`
- `scripts_p10/water_life.gd`
- 重新 build 的 `gen/water_life_p10.scn`

WLF gate 第 4 項與反向 N7／N8 改為檢查「P8 不被觸碰，且高架部材只有竜骨車」。

## 等價（`p8_equivalence.log`）
- 共 8677 個節點逐一比對：變換、網格陣列、材質、可見範圍、MultiMesh buffer（1844 個）、碰撞形、meta，**差異 0**。
- 撤去 26 個（6 群可見＋3 碰撞形，含子節點）。
- 新增 29 個，全部在 `FieldDetails/WaterSupply/Ryukotsu` 和 `Irrigation/WaterSupply`。同方向的部材合併成一個網格：`Trough/Body`、`Drive`、`Feed/Body`，水另成 `Trough/Water`、`Feed/Water`；柱、手摺、方杖仍是個別節點。
- `Post_00`／`Post_01` 這兩個名稱沿用給門形架柱的碰撞（形狀不同，log 已記錄）。

## FEEDER（使用者：「不能僅因節點不可見就放行」）
`walk_village_v2_farmland.gd --feeder` 原有項目全部保留，另外新增三項：
- `supply_system_state`：在 runtime 主場景（含所有 overlay）檢查取水構件全部可見、碰撞形全部有效、碰撞層 ≠ 0、高架樋殘骸 0。
- `source_ryukotsu`：檢查取水口在水面下且高於渠底、樋高於岸坡、送り樋高於地面、上端入り込み不互穿、張り出し高於桝壁、水位鏈單調下降。
- `ryukotsu_overlay_clear`：竜骨車部材 OBB 16 個；周邊可見網格頂點 3435 個、MultiMesh 實例 63 個，進入部材的都是 0。

結果 `feeder.log`：
- **0 失敗**。
- 相機：9 點、1620 姿勢，近接 0。
- 新增相機點 `ryu_head_n` 時，第一次 build 拐木近接 3 次；`RyuHead` 碰撞往外加大 0.2 m 後歸 0。

永久反向 `--feeder-negative`（`feeder_round3_state.log`，已併入回歸總表）：
- 樋 runtime 非表示、柱碰撞停止、殘留 `Chute_0`，三案都**正確 FAIL**。
- 還原後回到正常狀態。

## 效能（P8 runtime budget，`cost/`，1920×1080，單獨執行、無並行）
P8 開／關的 GPU 增量：

| 版本 | T1_eye（上限 6） | High_overlook（上限 4） | High_overlook draws Δ |
|---|---|---|---|
| R5b.1 前（ROUND 3 的 farmland_p8.scn） | +5.73 | +3.99 | +1522 |
| 第一版竜骨車（34 網格） | +5.58／+5.65 | +4.00／+4.02 | +1557 |
| 定版（合併成 16 網格） | +5.74／+5.71 | **+4.01／+3.97** | **+1521** |

- T1 視角看不到竜骨車，draws 前後都是 +528，數值差異是量測雜訊。
- High_overlook 在 R5b.1 之前就是 3.99，貼著 4.00 的上限。第一版竜骨車多了 35 個 draw，把它推到 4.00–4.02。
- 合併網格後 draws 比 R5b.1 前少 1，兩次量測分別是 4.01 與 3.97，仍在門檻上下跳動。
- 這個門檻邊緣的問題早已存在，`.hermes.md` 記錄為「P8 COST＝PRELIMINARY / UNRESOLVED」。R5b.1 對它的淨影響是 draws −1。
- 不放寬預算。

## 驗證一覽
- P8 local gate：0 失敗（`p8_build.log`）。
- P8 `--seal`：38 檔一致＋竄改反向（`p8_seal_after.log`）。
- R4b `--seal`：R4b 的 child_seals 包含 P8 封存，所以只在 R4b 的 `reseal_history` 更新子封存雜湊（kind `R5B1_CHILD_P8_UPDATE`），191 檔一致（`r4b_seal_after.log`）。
- WLF：plan＋反向 9/9 0 失敗、build、scene 0 失敗（P8 取水構件 all-on，overlay 開關前後都不變）。

## 審圖（`panels/`，乾淨渲染，Forward+ 10:00）
**BEFORE／AFTER 對照**：BEFORE 為 ROUND 3 狀態（高架樋被 runtime 隱藏、落とし桝斷頭）。
- `wlf_ww2_east_pair.jpg`
- `wlf2_ww2_east_tps_pair.jpg`
- `wlf_ww2_high_pair.jpg`

**竜骨車單張**：
- `r5b1_pump_tps_7m.jpg`
- `r5b1_pump_tps_12m.jpg`
- `r5b1_pump_canal_w.jpg`
- `r5b1_pump_feed_s.jpg`
- `r5b1_pump_high.jpg`

vision 自評：

| 視角 | 分數 | 主要問題 |
|---|---|---|
| 西岸隔渠（約 10 m） | 4/5 | 傾斜樋、羽根板、門形架都讀得出；下端入水與上端吐水不明顯 |
| 南側 TPS（feed_s） | 3/5 | 頭部在柳樹陰影裡；落水讀不出 |
| 高視角 | 3/5 | 下游（送り樋→桝→土渠）清楚；取水與上端被柳樹遮住 |
| 東側 TPS 7 m | 2/5 | 水車 2 佔滿畫面，竜骨車與它重疊，讀成「水車＋出水槽」 |

依使用者「不再新增美術迭代」：本輪**沒有**調整可讀性。剩下的可讀性問題列給 P13：
- 柳樹陰影。
- 吐水／落水的水花。
- 無操作者（NPC 擴張未授權）。

## 本輪不處理（明列）
- 水車 1／3（WW1／WW3 的 zone 取水）仍是「水車揚水到高架樋」這個前提，與 ROUND 3 以前的水車 2 相同。使用者裁定暫不修改。
- 竜骨車沒有操作者，畫面上是「使用中」的水位（樋內有水）。
- 送り樋碰撞頂約高出地面 0.6 m，與 `step_height` 0.6 相同，可能被當成台階踩上去。交 P11 實走確認。
