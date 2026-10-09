# P10 R5b.1 — IRRIGATION DESIGN REVIEW（Irrigation Source Reconstruction；設計審查，未施工）

使用者 2026-10-09 ROUND 3 FINAL §B：純動力水車方向接受；但 P8 灌溉系統失去水源，R5b 不能正式封存。先量上游水面、田面、水渠路線與可用高程，比較「上游自流取水／踏車等機械提水／有合理補水來源的溜池」，選最少改動既有地形與水道、機械與水位邏輯都成立的方案。不得憑空指定水源、不得違反高程、不得保留失去用途的斷頭水渠。FEEDER 不得只因節點不可見就放行。水車 1／3 不改。

**本輪只做量測與設計，未改任何 P8 檔案／水車／地形。** R5b 不封存。

## 1. 量測（`tools/survey_village_v2_irrigation.gd` → `survey.json`、`survey.log`；正式場景、碰撞射線＋水面 mesh 頂點）

| 水面／地面 | 高程（m） | 來源 |
|---|---|---|
| 主河 MainRiver（frame 內全段） | **−0.80**（全段一樣平） | Water/MainRiver 頂點 |
| 水渠 Canal 取水口段（388,−172）→（343,−90） | **−1.13** | Water/Canal 頂點（s 0–95 m） |
| 水渠（338,−60）→（336,−30） | −1.40 | 同上 |
| 水渠 水車 2 附近（332,0）→（300,90） | **−1.52** | 同上 |
| 水渠 下游（292,120）以南 | −1.63 | 同上 |
| P8 田面（farm_level，x 390–415、z 15–48） | **0.00**（田水 +0.045） | TLib.farm_level |
| P8 內渠水位 CH_WATER_S／N | 0.078／0.070 | farmland_lib |
| P8 地面木槽 TROUGH 底 | 0.11 → 0.08 | farmland_lib |
| P8 伏越し桝 SIPHON | 0.27 → 0.19 | farmland_lib |
| P8 上段土渠 UPPER（0.20 階面＋0.07） | 0.27 | farmland_lib |
| P8 落とし樋頭（已撤，原「水車 2 揚水 3.30」） | 3.30 | farmland_lib CHUTE |
| 田東側地形（x 440–540，z −100〜140） | −0.5〜−0.1（比田低） | 地形格子 |
| 田北側（x 380–420，z −72〜−8） | 0.8〜1.2（建成區台地） | 同上 |
| 東北台地（x 440–520，z −150〜−200） | 1.8〜2.1 | 同上 |
| 東北台地與田之間的窪地（x 440–540，z −120〜−136） | −2.2〜−3.0 | 同上 |
| frame 東緣丘（x ≈ 540） | 5〜7 | 同上 |

**結論：frame 內所有水面（最高＝主河 −0.80）都比田面（0.00）低 0.8 m 以上，比現存上段土渠（0.27）低 1.07 m 以上。本地形下沒有任何自流取水能到田。**

## 2. 正式場景的真實狀態（FEEDER 不放行的原因）

- WaterLifeP10 在 runtime 隱藏 P8 高架段：可視 `Chute_0／Chute_1／ChuteJoint／HeadBearer／Support_00／Support_01`，停用碰撞 `Post_00／Post_01／Chute_1`。`farmland_p8.scn`（P8 封存）裡它們仍然存在、碰撞仍啟用。
- 仍可見、但**已失去水源**的下游鏈：`DropBox`（落とし桝）→ 上段土渠 UPPER（水面 0.27 的水帶）→ `SiphonBox_0／1`（伏越し）→ `GroundTrough`＋地面木槽 Trough_0–4（槽內水 0.07）→ 內渠。這正是使用者說的「失去用途的斷頭水渠」：水面看得到，但沒有任何入水。
- FEEDER（`walk_village_v2_farmland.gd --feeder`）把 WaterSupply 下所有 MeshInstance 都當作可見，所以隱藏的 4 根支柱被判「可見但無碰撞」。**正確修法＝P8 limited correction 真的移除這些構件與碰撞**，不是讓 FEEDER 跳過不可見節點。

## 3. 三方案比較

| | A 上游自流取水 | B 機械提水（踏車／竜骨車） | C 溜池（有補水來源） |
|---|---|---|---|
| 水源 | 需要水面 ≥ ~0.35 的上游。frame 內最高 −0.80；主河在 frame 內是平的，**沒有任何量得到的上游高程** | 水車 2 旁的水渠（−1.52），已存在、已量 | 東北台地（~2.0）的池＋東緣丘（5–7）集水＋雨水 |
| 高程 | 要在 frame 外假設一條 ≥ 1 m 高的上游＋ 300 m 以上的新渠穿過村子 → **違反「不得憑空指定水源」** | 揚程 1.52＋0.27 ≈ **1.8 m** → 踏車 2 段（每段 ~0.9 m，中間溜め桝）或竜骨車 1 台（斜槽 5–6 m、~18°） | 池 ~1.8 → 田 0.0 可自流，但途中窪地 −2.2〜−3.0 與 −0.5 的低地 ~200 m → 需 1–4 m 的築堤／懸樋 |
| 改動 | 大：新渠、frame 外水源、P1/P2 | **小**：水車 2 東岸（落とし桝旁）一個提水站＋1 個溜め桝；下游鏈（DropBox→UPPER→SIPHON→TROUGH→內渠）**全部原樣再利用**；撤掉已隱藏的高架段 | 大：新池（P1 地形）、長築堤／懸樋（又是高架渠，使用者不要）、P1／P2 |
| 機構／水位邏輯 | 不成立（沒有上游） | 成立：人力把水渠水抬到 0.27 → 自流 0.27→0.19→0.08→0.078→田 0.045 | 水位成立；但補水來源（frame 邊緣以外的丘）只有一部分在地圖上 |
| 封存影響 | P1／P2／P8 | P8 limited（見 §4）＋P7 河岸 kit 局部確認 | P1／P2／P8／P7 |

**建議：B（機械提水）。** 優先：**竜骨車 1 台**（斜槽 5–6 m，下端在水渠水中、上端出水進落とし桝；腳踏輪；江戶以前日本實用，揚程 1–2 m 的記錄）。備選：**踏車 2 段**（每段 ~0.9 m；中段溜め桝挖在岸坡上）。兩者都是人力、都是水渠旁的低矮設備（最高 ~1.6 m），不是高架渠道，也不宣稱水車揚水。水車 2 維持純動力（精米等用途仍只是提案）。

## 4. B 方案的 P8 limited correction（需使用者授權後施工；本輪未改）

受影響封存檔（`data/village_v2_p8_seal.json` frozen）：
- `tools/village_v2_farmland_lib.gd`：刪 CHUTE／CHUTE_POST_T／高架落とし樋碰撞（`Post_00／01`、`Chute_1`）；加提水站（竜骨車斜槽＋腳踏台）的碰撞與常數（位置＝DROP_BOX 西側岸坡，x ≈ 336–338.7、z ≈ 3–5）。
- `tools/village_v2_farmland_visual.gd`：`_supply_art` 刪 Chute／ChuteJoint／HeadBearer／Support；加提水站的可見構件（或新 asset；材質依 V2_Wood＋P8 已核准木色，**取代 `p8_tone` runtime 調暗**＝正式的材質規範）。
- `maps/village_v2/gen/farmland_p8.scn`（重烘；MultiMesh 規則：非 headless＋回讀）。
- 不變：`village_v2_farmland_zone.gd`、兩個 shader、`p8_blocks.json`、`p8_ground.json`（若提水站不改田區塊）。
依賴：`verify_village_v2_farmland.gd`（水位鏈 gate：新增「提水站出水 ≥ 上段土渠水位」）、`walk_village_v2_farmland.gd --feeder`（照原規則驗新形狀：可見支柱都有碰撞、路權淨空、FarmPath_1／稗田邸前實走）、P8 seal reseal（前後雜湊＋reseal_history＋反向）、WaterLifeP10（撤掉 runtime 隱藏與 `p8_tone`、WLF gate 改成「P8 不再有高架段」）、P7 河岸 kit（提水站位於岸坡，需確認與 riverbank_kit 構件不互穿；不改 P7 檔）。
不做：水車 1／3、第二艘船、精米小屋、地形改動。

## 5. 待裁定
1. 是否採 B（竜骨車 1 台／踏車 2 段二選一）。
2. 授權 P8 limited correction（上列檔案）＋P8 reseal。
3. 在那之前：R5b 維持 ART_REVIEW（純動力水車方向已接受），FEEDER 與 WLF 的 Expected Pilot Seal Conflict 照實保留。
