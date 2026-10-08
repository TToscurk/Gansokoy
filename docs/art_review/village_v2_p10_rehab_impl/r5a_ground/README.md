# P10 R5a — Ground Pilot：道路外緣＋田格外溢（ART_REVIEW・未核准）

使用者 2026-10-09 D3（Road base regeneration：CONDITIONAL）／D4（P7 ground shader：LIMITED FIX）。

## 根因（MASTER AUDIT R5a-01／02）
- **道路＝等寬直邊 ribbon**（`gen_village_v2.gd _ribbon`）：外緣是一條幾何直線＋材質斷層。
- **第二套田格**：P7 `ground.gdshader` 93–104 行在 farm 權重 > 0.001 的地方程序畫 24×16 m 田格與畦。P8 每塊田都有自己的
  WetMudBottom／畦網格（farm 權重 0），所以這張格只會在 **P8 田外**（路肩、田間、羽化帶）露出 → 「田地材質混入道路」。

## 做法（不改封存檔、不重生 base）
- **pilot shader**＝讀封存的 `ground.gdshader`（雜湊須＝`matlib.json` 封存值）做 6 段**文字補丁**產生 `maps/village_v2/shaders_p10/ground_p10_pilot.gdshader`：
  1. 田格段 → 不畫規則格；farm 權重只給不規則「田邊耕土」斑（`farm_soil` 0.32）
  2. 道路帶外緣侵蝕：沿路低頻寬度起伏（`edge_irreg`）＋沿路拉長的草舌（`edge_w`）＋細鋸齒，`discard` 切出不規則外緣；深度上限＝半寬 × 0.35
  3. 切口內 0.4 m 先混草（不是一刀從土切到草）
  4. 田埂道中央草帶斷續化（`center_patch`）
  5. （R6b 用）參道石段範圍挖掉 ribbon 中央（`cut_s`／`cut_hw`，預設關）
  新參數預設＝舊行為：沒被指名的道路不變。
- overlay `GroundPilotP10`（`gen/ground_pilot_p10.scn`，AlbedoPilotP10 之後）：執行期把 Terrain 4 段（田格修正）＋ Pilot 道路 4 條
  （南橫街〔町→田〕、田埂道 1／4〔農道〕、河岸小徑〔水岸〕）的材質換成 pilot shader 複本（原參數逐一保留）；`enabled=false` 還原。

## 參數（核准範圍內）
| 道路 | edge_w | edge_irreg | center_patch | 用途 |
|---|---|---|---|---|
| CrossStreetSouth | 0.55 | 0.30 | 0 | 町→田 |
| FarmPath_1／_4 | 0.40 | 0.26 | 1.0 | 農道 |
| RiversidePath | 0.60 | 0.32 | 0 | 水岸 |
外緣實測（CPU 以同一張 V2G_noise.png 重算 shader 侵蝕式）：各側外緣位置沿路標準差 0.12–0.22 m（核准 0.08–0.45）。

## 迭代（停止規則：3 輪後停）
| 輪 | 變更 | Agent 自評（vision，非 ART 判定） |
|---|---|---|
| r1 | 田格移除＋外緣侵蝕 | 高視角 4/5、農道 TPS 4/5 |
| r2 | 加細鋸齒 | 近距 6 m 3/5（缺口像印章） |
| r3 | 草舌沿路拉長＋切口內混草 | 近距 6 m 3/5（輪廓仍偏圓）——停 |
| 最終 | （r3 定版） | 田格高視角 4/5（錯誤田格消失；侵蝕邊略塊狀）、農道 TPS 4/5（中央草帶不明顯、缺局部凹陷） |

## 未做／阻礙
- **base 重生（D3）本輪未做**：外緣用 shader 解決；R5a-04 的局部浮邊（丘腳街橋頭 1.46 m、河岸小徑 0.59 m）與 ribbon 浮 0.06–0.10 m 仍在，
  要根治需重生 `gen/road_*.res`（最小作用域、先快照、驗 P3 依賴）——列為下一輪。
- 近距 6 m 的草侵入輪廓仍有「遮罩感」：根治需要真的草幾何（MeadowP9 已封存，不動）或路緣專用的植生 overlay。
- 全面套用（ART_APPROVED 後）：補丁併入 `tools/build_village_v2_textures.py` ground shader 模板 → 重生 `ground.gdshader` →
  `matlib.json` files_sha256／`_matlib` gate.json／registry（P7 `_matlib` limited reseal，依 D4）；道路參數併入 `gen_village_v2.gd ROAD_GROUND`。
