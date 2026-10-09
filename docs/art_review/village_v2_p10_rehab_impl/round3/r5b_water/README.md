# P10 R5b ROUND 3 — 水車 2「純動力水車」Pilot（ART_REVIEW，未 ART_APPROVED）

使用者 ROUND 3 §1：停止揚水方案，撤除 ROUND 1／2 的柄杓・受け樋・架台・注ぎ・樋の流れ；水車 2 定義為純動力（下掛け）水車。

## 本輪內容（`tools/village_v2_water_life_lib.gd`→`gen/water_life_p10.scn`→root `WaterLifeP10`）
- overlay 內揚水部材 0 件（gate「動力水車」＋回讀）。
- 水流方向與受力一致：輪下端（葉板先端）移動方向 · 水渠下流方向 ＝ 1.000（RotorAnim spin；scene 實測下端移動 1.27 m）。
- 葉板浸水 0.35 m（0.15–0.80），離渠底 0.92 m。主泡在輪心下流 z +2.05（葉板出水側）。
- 保留：水輪、Hero 支架、渠岸、小舟 1（D10）、繫船杭、荷。水車 1／3 不動（gate：揚水部材 0）。
- **P8 落とし樋高架段（`Chute_0`、`HeadBearer`：可視 6／碰撞 3）＝ runtime 隱藏的 Pilot override**（`enabled=false` 即恢復顯示與碰撞；P8 檔案未改）。
  DropBox 以下（上段土渠・伏越し・地面木槽・內渠）不動。P8 落とし樋木部的 runtime 調暗（`p8_tone`）照舊，僅為 Pilot override。

## 證據
- gate：`gate_plan_negatives.log`（0 失敗、反向 9/9）、`build.log`（表裏 0／1440）、`gate_scene.log`（0 失敗）。
- 三聯（BEFORE｜ROUND 2｜ROUND 3）：`panels/wlf2_ww2_west_tps_tri.jpg`、`wlf2_ww2_east_tps_tri.jpg`、`wlf_ww2_east_tri.jpg`、`wlf_ww2_high_tri.jpg`、`wlf_ww2_8m_tri.jpg`、`r5b_ww2_chute_tri.jpg`。

## 自評（vision，同機位三聯）
| 視角 | 分數 | 主要問題 |
|---|---|---|
| 西 TPS | 3/5 | 葉板入水與泡太弱、流向不夠一眼可讀；輪後方一段橫向暗構件讀成殘留槽 |
| 東 | 3/5 | 前景 P8 落とし桝與灌溉渠失去水源、看起來斷開；陰影遮住下端入水 |
| 高視角 | 3/5 | 流向可讀（左上→右下）；輪右後方一段短槽狀殘件（P8 DropBox 附近）無來源 |

## Remaining issue／替代方案（本輪不做）
1. **P8 灌溉來源（需 limited correction 授權）**：P8 r5 的取水鏈＝「水渠 → 水車 2 受け樋 3.30 → 落とし樋 → 上段土渠 → 伏越し → 木槽 → 內渠」。
   水車改純動力後此鏈沒有水源。量測：水渠水位 −1.52、田面 0.20（差 1.72 m）→ 本地不可能自流取水。
   選項：(a) 上游取水口（主河 H3 段或西渠）沿等高線引土渠自流——需地形調查與 P1／P2 依賴確認；(b) 踏車（足踏み水車，揚程約 0.5–1 m）＋溜め桝分兩段——人力揚水，屬 P10 human-use；(c) 溜池（丘側）自流——新地形要素，影響最大。
   **受影響封存檔**：`tools/village_v2_farmland_lib.gd`（CHUTE／DROP_BOX／UPPER／SIPHON／TROUGH、`_supply_body` 碰撞）、`tools/village_v2_farmland_visual.gd`（`_supply_art`）、`tools/village_v2_farmland_zone.gd`、`maps/village_v2/gen/farmland_p8.scn`、`data/village_v2_p8_seal.json`；依賴：`verify_village_v2_farmland.gd`（水位鏈 gate）、`walk_village_v2_farmland.gd`、`probe_village_v2_farm_blocks.gd`、本 overlay 的 `p8_tone`／落とし樋隱藏。
2. **正式版不可依賴 runtime 覆寫**：落とし樋隱藏與 `p8_tone` 調暗都是 Pilot override；ART_APPROVED 後要以 P8 limited correction（改 lib 常數＋重烘 farmland_p8.scn＋P8 reseal，含前後雜湊與反向）取代。
3. **可讀性**：若需 4/5，可再加強下端入水處的白波與流線（不新增建築）；精米小屋等機械用途只提方案（例：輪軸東側加小屋＝新建物，需另案）。
