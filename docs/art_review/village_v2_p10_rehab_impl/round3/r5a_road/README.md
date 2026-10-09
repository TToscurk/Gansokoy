# P10 R5a ROUND 3 — Road Base：舊路寬筆直土色帶的根因與修正（ART_REVIEW，未 ART_APPROVED）

## 1. 切分診斷（使用者 §3 A–D）
工具：`tools/diag_village_v2_road_band.gd`（同機位、Forward+、10:00；只讀）。每機位 6 張：
V0 現行／**A** RoadBaseP10 關閉／**B** 隱藏 3 條道路 Mesh（只剩地形）／**C** B＋把地形 shader 的 trodden／street 頂點權重歸零（隔離 P7 road weights）／**D** 權重可視化（R street、G trodden、B farm）／E B＋隱藏 P9 地被。
- 修正前（`band_diag/`，`*_sheet.jpg`、`band_diag.json`）：B 仍有與舊路同寬的筆直土帶；C 消失；D 的帶＝**G（trodden）**；E 與 B 相同。
  B→C 平均色差：farmpath4 6 m 6.75、cross_south 8 m 7.98、farmpath1 5.92、高視角 2.61（B→E 只有 0.66–1.2）。
- **根因＝P7 地形頂點權重**：`gen_village_v2.gd` `_road_halo` 把道路芯 hw−0.3〜hw＋1.6 m 寫進 FarmlandTerrain 的 COLOR.r（trodden），
  地形格子 2 m、線性內插 → 帶寬≈舊路寬＋兩側 2 m 且筆直。不是 Road Mesh、不是 P9 地被、不是 pilot shader 的條件。
  另一個量測結論：只把畫刷縮成新路寬不夠——格子 2 m 時，格點 ±2 m 的值仍會內插成 4 m 寬的直帶（FarmPath_1 就在 x＝372 格列上）。

## 2. 修正（P7 limited correction 的 Pilot，runtime；不覆寫封存檔）
- `tools/village_v2_road_base_lib.gd` `terrain_fix()`：用與 gen 相同的式子重算「對象 3 條的舊帶」與「其他道路・巷道的帶」，
  只改**對象舊帶佔主導**的頂點（tr0＝0.85·max(對象, 其他) ±0.04 且 對象 ＞ 其他），重新塗成再生道的芯・寬・使用量：
  塗刷只在路面內側（半幅 −0.6 m、halo 0–0.3）且寬度 × traffic（田的深處＝0：路的土色只由再生道 Mesh 提供）。
- 只改 COLOR.r（577／13703 頂點）；位置・UV・UV2・索引完全一致、法線・接線差 ≤ 1e-3（同壓縮旗標的再量化）、COLOR.gba 不變。
- RoadBaseP10 runtime 換 `Terrain/FarmlandTerrain` 的 mesh；`terrain_farmlandterrain.res` sha256 build 前後一致；`enabled=false` 還原。
- gate RDB 新增 T1–T3＋反向 N6（放寬判定 → 改到其他道路）／N7（移動頂點）：plan 0 失敗、反向 7/7；scene 0 失敗（`gate_plan_negatives.log`、`build.log`、`gate_scene.log`）。

## 3. 修正後
- `band_diag_after/`：B→C 平均色差 farmpath4 6.75→**0.67**、cross_south 7.98→**2.47**、高視角 2.61→**1.45**、farmpath1 5.92→3.91
  （farmpath1 的剩餘＝再生道路面內側仍保留的使用痕跡＋視野遠處村側區段）。
- 三聯（BEFORE｜ROUND 2｜ROUND 3）`panels/`，vision 自評：
| 視角 | 分數 | 主要問題 |
|---|---|---|
| farmpath4 6 m `grd_farmpath4_6m_tri.jpg` | 4/5 | 土／草交界局部太硬；寬度與磨損變化不足 |
| cross_south 8 m `grd_cross_south_edge_8m_tri.jpg` | 4/5（ROUND 2 同圖 3/5） | 交界缺少稀草・砂・小石的漸層；部分缺口像切出來 |
| farmpath1 10 m `r5a_farmpath1_n_tri.jpg` | 4/5 | 右側交界突兀；淡淡的平行路肩痕 |
| 高視角 `r5a_farm_road_high_tri.jpg` | 4/5 | 未再生的其他田間小路仍是筆直帶，與再生道不一致；交叉口過寬 |

## 4. Remaining issue／替代方案
1. 土／草交界偏硬：可在 pilot shader 的路肩帶加入「稀草＋砂利」過渡（屬再生道 Mesh 自身的條件，不是遮罩）；或再生道邊緣加 0.3–0.6 m 的低密度過渡頂點列。
2. 其餘田間小路與巷道未再生（本輪範圍只限 3 條、≤ 450 m）：全村擴張需另行授權，且同樣要處理 P7 頂點權重（本機制可沿用）。
3. 正式版：ART_APPROVED 後，P7 地形的 COLOR.r 修正需以 limited correction 進 gen（或封存檔重烘）＋P7 reseal（前後雜湊・依賴：MeadowP9／GroundcoverP9 只讀地形高度不讀權重〔待 reseal 時再驗〕）。
