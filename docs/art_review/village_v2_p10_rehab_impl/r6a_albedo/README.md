# P10 R6a — 材質亮度基準＋街區調色盤 Pilot（ART_REVIEW・未核准）

使用者 2026-10-09 D8：**Albedo calibration DO NOW, PILOT FIRST**——以色卡與代表建築驗證，不一次改全村；P13 天光另案。
優先順序第 2（材質亮度基準）＋第 6（建築差異）——兩者共用同一個 overlay，Pilot 範圍相同。

## 根因（MASTER AUDIT R6a-01）
- `_matlib` 建物材質 V2_Plaster／Wood／Kawara、machiya_kit 的 V2_KitStoneTri／V2_MachiyaKit 全部 `albedo_color 0.42`（P1 時期為 Compatibility renderer 校正的係數），沿用到 Forward+。
- 色卡實測（`albedo_cal.json`／`albedo_cal_cards.png`，10:00 日照、垂直面）：18 % 灰卡 luma 0.647、50 % 灰卡 0.905；白漆喰在 0.42 時只有 **0.431**——比 18 % 灰卡還暗 → 「整村灰暗」。
- 町家 Kit 的 LOD1/2（`l_*` 網格）把屋根灰（0.42）、漆喰（0.87）、木（0.20）畫在同一張 atlas 上；單一係數提亮會連遠景屋根一起變淺（r1–r3 高視角審圖「屋面淺灰」的原因）。

## 做法（overlay，不改任何封存檔）
- `tools/village_v2_albedo_pilot_lib.gd` → `maps/village_v2/gen/albedo_pilot_p10.scn` → root `AlbedoPilotP10`（EdgeClosureP10 之後），script `maps/village_v2/scripts_p10/albedo_pilot.gd`：
  執行期對 Pilot 建物的表面做 surface override；`enabled=false` 全部還原。
- Pilot 範圍：A 入口〜南大鳥居〜主街南段（12 棟）、B 西巷住宅（12 棟）＝ 24／187 棟（12.8 %）。
- 校正值（色卡實測選定）：漆喰 0.70（luma 0.718）、木 0.75（0.413）、基石 0.65（0.522）、**瓦不校正**（0.42）。
- 町家 Kit atlas：等價 shader `maps/village_v2/shaders_p10/kit_cal_p10.gdshader`（貼圖／粗糙度／發光＝原材質），依 atlas 色階分類：暗（木）→ 0.75、中（屋根灰／暖簾）→ **0.42 不變**、亮（漆喰／障子）→ 0.70 → LOD0 與 LOD1/2 同一套，屋根不變淺、40 m LOD 切換牆面不跳亮度。
- 街區調色盤（建築差異）：每棟依節點名雜湊挑一組（漆喰 4 × 木 3），14 m 內鄰棟不同組；飽和度 ≤ 0.22、亮度留在色卡帶。
  A 商業＝暖白／生成り漆喰＋飴色・紅殻・素木；B 住宅＝帶灰／土色漆喰＋風化灰・煤色木。

## 迭代紀錄（停止規則：4 輪後停）
| 輪 | 變更 | Agent 自評（vision，非 ART 判定） |
|---|---|---|
| r1 | 漆喰 0.75／木 0.75／瓦 0.58／Kit 0.80 | 立面 12 m 4/5；高視角 3.5/5（屋面偏淺） |
| r2 | 瓦 0.50 | 高視角 3/5（遠景屋面仍淺） |
| r3 | 瓦不校正、漆喰 0.70 | 主街 TPS 4/5；高視角 3/5（遠景屋面仍淺→查出是 Kit LOD atlas） |
| r4 | Kit atlas 色階分類 shader | 高視角 3/5（屋面變穩定；牆「太乾淨均一」） |
| r5 | ＋街區調色盤 | 南大鳥居→主街 TPS 4/5、入口高視角 4/5（前景漆喰略白、Pilot 內外反差）、西巷住宅 TPS 4/5（牆面仍乾淨均一） |

## 驗證
- plan＋反向（`gate_plan_negatives.log`）：來源＝0.42、只改 albedo（Kit＝等價 shader）、色卡 luma 在目標帶、24 棟兩區、≤ 25 %、調色盤；反向 7＋2（帶色／等幅提亮／區外／全村／改粗糙度／Hero／Kit 屋根提亮／過飽和／全同組）全部正確 FAIL。
- scene（`gate_scene.log`）：掛載順序、Pilot 建物的來源材質表面全部覆寫、Pilot 外 0、開關還原、來源檔雜湊不變。

## 已知限制（non-blocking 候選）
- Pilot 邊界：高視角看得到「已校正／未校正」兩種亮度並存（Pilot 本質）。
- 牆面「乾淨、均一」是貼圖／汚し層的問題，不是 albedo 能解；全村套用時建議與 R6a 汚し（雨垂れ・腰の泥はね）一起做。
- 全村套用（ART_APPROVED 後）＝改 `matlib.json` albedo_k＋.tres、Kit atlas 重烘 → `_matlib`／machiya_kit Asset Gate＋registry（P7／P6 limited reseal）。
