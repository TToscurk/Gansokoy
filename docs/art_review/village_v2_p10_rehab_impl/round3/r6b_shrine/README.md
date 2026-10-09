# P10 R6b ROUND 3 — 參道石段：walkable-surface 驗證、ARM_PULL 根因、局部老化（ART_REVIEW，未 ART_APPROVED）

## 1. 本輪內容
- 保留三個踊り場（ROUND 2 設計基礎）與斜坡碰撞（D7），碰撞形狀未改。
- 美術（lib ART_REVISION r9，只改可見石）：踏面奥・入隅の土と落葉、鼻先の角欠け 12 %、目地の苔、差し替え石（色違い）6 %；
  苔 quad 的捲繞修正（表裏 gate：石段 0／6364・基壇 0／60）。不加燈籠、不加裝飾物。
- 新 gate **SWALK**（`tools/verify_village_v2_sando_walkable.gd`）＝提案中的 P9 R4-2 scope-aware／walkable-surface verifier correction。
  **P9 R4-2 的封存 gate 未修改**（仍為 Newly Introduced 衝突，見回歸分類）。

## 2. SWALK（`walkable_gate.log`，0 失敗、反向 5/5）
足場＝該點最上面的可行走面（P1 地形或參道斜坡碰撞），其他碰撞體（樹・燈籠・鳥居）不當足場；高度閾值未放寬：
| 檢查 | 結果 |
|---|---|
| W1 可行走面位置：斜坡碰撞 vs 可見踏面 | 最大 0.114 m（≤ 半蹴上 0.10＋0.03） |
| W2 玩家膠囊淨空（r 0.30 h 1.70，player_yoriichi 實寸，中心＋左右 ±0.85） | 接觸 0 |
| W3 上下平台高度連續（每 0.25 m） | 最大 0.187 m（≤ 0.25·tan 52°＋0.02＝0.340） |
| W4 平台邊緣與兩側 | 袖石外緣 ≤ 斜坡半幅＋0.05；縁內＝踊り場高；側面掉下 8 m 內可回到參道 |
| W5 NPC 巡回 | 初期位置在石段上 0；巡回 6 條不橫切石段 |
| W6 正式 TPS 相機 | 上下行 532 點，相機進入石／地形 0 |
| W7 與 P9 R4-2 相同路線（179 點、膠囊足場＋0.55） | 被擋 0 |
反向（每案必失敗）：參道放 1 m 箱／踊り場斜坡抬 0.5 m／踊り場斜坡挖洞／斜坡縮成 2.0 m 寬／相機碰撞關閉。
參考（INFO）：用 P9 R4-2 封存 gate 同樣的「地形基準」膠囊測此場景 → 179 點中 40 點被擋，被擋處足場比地形高最多 0.94 m（＝踊り場盛土上的實際行走面）。

## 3. ARM_PULL（下行相機被拉近）根因
**診斷**（`tools/diag_village_v2_sando_camera.gd`，`camera_diag*.json/log`）：沿中心線每 0.25 m 模擬下行玩家＋正式 SpringArm（Pivot 1.65、pitch −0.18、腕 8.5、margin 0.2）。
| 構成 | 腕被拉近（< 0.55×8.5）比例 | 次數 | 最短 | 相機入石 |
|---|---|---|---|---|
| A 只有地形 | 73 % | 2 | 2.99 m | 0 |
| B 無踊り場（ROUND 1 一本斜坡） | 73 % | 2 | 1.31 m | 0 |
| C ROUND 2/3 踊り場 3 | **55 %** | **5** | 1.46 m | 0 |
| C，pitch −0.35（相機抬高約 10°） | 5 % | 1 | 1.54 m | 0 |
| C，pitch −0.50 | 4 % | 1 | 1.67 m | 0 |
- **根因＝30° 坡 vs 預設 pitch −0.18**：腕向後上方只抬約 10°，下行時身後是 30° 上坡 → 腕撞到坡面（只有地形時也 73 % 被拉近）。
  不是階梯 Mesh（相機入石 0）、不是斜坡碰撞特有（A 只有地形同樣 73 %）。
- **1 → 5 次的原因＝平台高度**：踊り場讓坡在 3 處變平，腕在那裡短暫伸回 5.3–5.8 m（> 4.68 門檻）→ 一段長的拉近被切成 4–5 段。
  總拉近比例反而下降（73 % → 55 %），但次數上升、鏡頭距離在 3.5 ↔ 5.5 m 間脈動。
- 最短 1.46 m 在頂端 s≈101.5（起步點身後的社殿前 `Collision`），所有構成都有。
- **實走**（正式 main.tscn F5 路徑、pitch 固定 −0.18，`walk/walk_log.json`）：下行 ARM_PULL 事件 ROUND 2＝5 → ROUND 3＝4；上行 0。
  （第一次 ROUND 3 實走起動時 pitch 被滑鼠事件改成 +0.338，相機條件不同 → 作廢不採用；`walk_p10_final.gd` 新增 `--pitch=` 固定初始 pitch。）

**處理（本輪未改相機程式，需授權）**：不關相機碰撞。可行方案＝相機轉接器在陡坡下行時把目標 pitch 偏到 ≈ −0.35（模擬：拉近 55 % → 5 %、次數 5 → 1，相機入石 0）；
或「拉近即時、伸回平滑」的 SpringArm 長度遲滯（模擬：在本段的伸回區間太長，次數不減，單獨無效）。前者需改 `characters/yoriichi/player_camera_adapter.gd`（玩家相機；另一 session 正在改 yoriichi 相關檔）→ 只提案。

## 4. 美術自評（vision，同機位三聯 BEFORE｜ROUND 2｜ROUND 3）
| 視角 | 分數 | 主要問題 |
|---|---|---|
| 下行（石段上） `panels/san_steps_down_tri.jpg` | 3/5 | 鼻先一致性仍高；袖石與踊り場接縫處的暗縫突兀 |
| 踊り場上往下看 `panels/san2_down_landing_tri.jpg` | 2/5 | 前景大平石遮住下一段；老化讀成幾何塊狀 |
| 往上看踊り場 `panels/san2_up_landing_tri.jpg` | 2/5 | 邊緣直、完整；局部磨損太少、平台石板像新組裝 |
實走影片：`walk/seg1_end_vista_2x.mp4`、`walk/seg2_steps_up_2x.mp4`、`walk/seg3_steps_down_2x.mp4`。

## 5. Remaining issue／替代方案（依停止條件，本輪不再迭代）
1. 程序化方塊石在 TPS 距離下老化細節讀不出（2–3/5）。替代：(a) 用 CC0 掃描石段／石材 kit 取代程序方塊（P5 式 Asset Gate）；(b) 曲率／AO 驅動的邊緣磨損 shader（需材質規範）；(c) 鼻先不規則化（每段 ±3–5 cm 前後錯位＋圓角）。
2. ARM_PULL：見 §3，需相機轉接器授權。
3. P9 R4-2：ART_APPROVED 後以 SWALK 的「最上面可行走面」做 limited verifier correction＋reseal（前後雜湊、反向保留）；在那之前舊 gate 維持 FAIL。
