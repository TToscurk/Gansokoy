# P13 WAVE 3B — 土渠美術正式整合（N0／T0）最終報告

狀態：**ART_REVIEW，等待使用者驗收**。未 ART_APPROVED、未 push。範圍止於 N0／T0 土渠，未進入神社、道路、其他建築美術。commit `e50c84c` 保留。

**結論（一段話）**
W3 已批准的材質方案（渠底濕泥 → 內坡泥土 → 堤頂踏實土 → 外坡草，沿渠不規則變化；較暗、較粗糙的泥水面）已寫進生成器，套用 N0＋T0 全部 92.1 m 土渠（含原本全黑的 T0 上游）。`farmland_p8.scn` 正式重烘、P8 limited reseal 完成、`CanalSampleP13` 預覽 overlay 已移除。木槽下的暗縫經實測是**真實的 3.3–21.6 cm 間隙**，用一條貼地的低矮盛土填實；水面高程、坡降、伏越し、道路、碰撞不變。
殘留與未驗證項見 §6、§7（T0 木槽頭的暗凹、端點接到範圍外仍是黑色的渠段、視覺判讀僅為輔助）。

**證據等級**：「量測」＝腳本／像素統計，可重跑；「gate」＝永久驗證；「視覺模型判讀」＝輔助讀圖，**不是美術判定**，也不保證穩定（同一張圖兩次判讀可能不同）。

## 0. 與指示逐項對照

| 指示 | 結果 |
|---|---|
| 1 材質權重漸變＋沿渠不規則＋泥水材質方向 | 已整合（§2）。反射保留，只收斂刺眼白高光（§6 數字） |
| 2 套用 N0、T0 全部土渠（含黑色上游）；不擴展主河道；重烘一次；limited reseal；移除預覽 overlay | 已做（§1、§2）；主河道、其他水體、其他渠段未動 |
| 3 木槽接縫／暗縫：先查原因、最小修正、不用大型遮擋物、不動水位／坡降／伏越し／道路／碰撞 | 原因＝真實間隙；修正＝貼地盛土（§3）。**注意：這是新增幾何（+1580 三角形、無碰撞），不是只改材質**；若你認為它算「遮擋」，回退 zone.gd＋farmland_p8.scn 即可 |
| 4 邊坡外緣：只修 TPS 明顯可見者，優先材質、不重新細分 | 只做材質：外縁固定為草，網格三角形數不變（N0 1764→1764） |
| 5 MKT_018 | 接受上次複測，本輪未重測、未改角色／相機 |
| 6 測試範圍 | 只做 P8 局部＋封存依賴＋反向＋一次代表性 TPS 通行＋同鏡位 Before／After；未跑全村實走與完整回歸（§7） |
| 7 交付 | 本檔；commit 見 §7 |

---

## 1. 正式整合的土渠範圍

由 `FLib.plan()` 唯讀印出（`evidence/branch_composition.log`）：

| 支線 | 區段 | 起訖（世界 x,z） | 長度 | 處理 |
|---|---|---|---|---|
| N0 | run0 土渠 | (359.5,5.6) → (360.0,2.0) | 3.6 m | 漸變材質＋泥水 |
| N0 | 伏越し | (360,2) → (361,−2) | — | 不動 |
| N0 | run2 土渠 | (361,−2) → (360,−31) | 31.9 m | 同上 |
| N0 | 伏越し | (360,−31) → (357,−39) | — | 不動 |
| N0 | run4 土渠 | (357,−39) → (352.4,−45.2) | 8.0 m | 同上 |
| T0 | run0 木槽（竜骨車送り樋側） | (338.1,5.1) → (338.0,12.1) | 8.4 m | 槽下盛土＋泥水（槽本體不動） |
| T0 | run0 土渠（上游，原先全黑） | (338.0,12.1) → (334,37) | 26.2 m | 漸變材質＋泥水 |
| T0 | 伏越し | (334,37) → (335,46) | — | 不動 |
| T0 | run2 土渠 | (335,46) → (331.7,49.7) | 5.0 m | 漸變材質＋泥水＋口絞り |
| T0 | run2 木槽 | → (327.0,54.9) | 6.9 m | 槽下盛土 |
| T0 | run2 土渠 | → (327.0,60.2) | 6.0 m | 漸變材質＋泥水 |
| T0 | run2 木槽 | → (329.0,67.5) | 7.9 m | 槽下盛土 |
| T0 | run2 土渠 | → (330.2,78.0) | 11.4 m | 漸變材質＋泥水 |

土渠合計 **92.1 m**（N0 43.5＋T0 48.6），木槽 23.2 m。W3 樣本只覆蓋 T0 run2（伏越し出口 (335,46) → 末端 (330.2,78)，見 `wave3/P13_WAVE3_IRRIGATION_ART_REVIEW.md` §2）；這次加上 T0 run0 與整條 N0。

**未動**：P8 其他渠（上段土渠、各塊 `LateralBed`／`MainBed`／`DrainBed`、逐階水路與排水口）、竜骨車、水車、P2 主河道與其他水體、道路、田。

---

## 2. 實際修改的生成器、材質與封存

**生成器（Source of Truth；非 Editor 手改）**
- `tools/village_v2_farmland_zone.gd`（+131／−5）：`branch_bank_weights()`（頂點地面重み）、`branch_water_mat()`（支線專用泥水）、`trough_bed*()`（木槽下盛土）、`water_neck()`（木槽口的水幅）；`branch_art()` 改為頂點逐點重み、collar 先端漸減為草、水面材質換新。
- `tools/village_v2_farmland_visual.gd`（+19／−8）：`_ribbon()` 增加 3 個**可省略**參數（`wfn` 頂點重み、`ucols` 橫斷列位置、`hscale` 半幅倍率）。未指定時，既有 ribbon 與改前相同——由下方的逐節點等價比對支持（其餘 8813 個節點完全相同）。

**材質**
- 土渠地面重み（ground shader 的頂點色＋UV2）：渠底＝濕泥（濕 0.85）→ 內法＝泥→土 → 堤頂＝踏實土（沿渠方向用決定性 hash 變化土量與土質）→ 外法＝草；**外縁（|u|＝1）固定為草**，與地形相接不留直線切口。改前＝全幅同一組 `COLOR(0.12,0.25,1.0,0)／UV2(1,0)`（泥 100 %、濕 1.0）。
- 木槽接合的 collar（土渠延進槽下 1.2 m 的部分）先端以 `smoothstep` 漸減為草。
- 支線水面（土渠＋木槽共用一材質，只限 N0／T0）：tint (0.22,0.20,0.13)、clarity 0.42、rough_base 0.34、algae 0.25、scum (0.27,0.24,0.16)；改前 tint (0.36,0.36,0.30)、clarity 0.7、rough 0.2。`p8_paddy_water.gdshader` 本身未動。

**重烘與等價**（`evidence/p8_build.log`、`p8_equivalence.log`）
- `verify_village_v2_farmland.gd -- --build`（非 headless）正式重烘，檔案 55,392,676 → 55,426,679 bytes，新雜湊 `536f2599…b848c`。（調整內坡權重時曾多烘過一次；留下的是最後一次。）
- 逐節點比對 8817／8817：**一致 8813（含 MultiMesh 1844 個 buffer）**；差分 4 個＝`Branch_N0/Merged_0`（網格）、`Branch_N0/Merged_1`（材質）、`Branch_T0/Merged_1`（網格＋材質）、`Branch_T0/Merged_2`（網格）；old 獨有／new 獨有＝0。
  - N0 土渠 1764 → 1764 三角形，位置全同，只換頂點色／UV2。
  - T0 土渠 2184 → 3764 三角形，舊三角形一個沒少，多出 1580＝木槽下盛土。
  - 水面：N0 頂點全同；T0 頂點 1488→1488、index 同一，120 個頂點在木槽口 x/z 內縮（最大 0.126 m），**y 最大差 0.29 mm**。
  - 碰撞形、MultiMesh、田、取水（竜骨車）：逐節點相同。

**封存（limited reseal，`tools/p13/reseal_w3b.py`）**——allowlist 方式，本輪外任何 frozen 不一致即中止；腳本結束時全部 seal 比對 0 不符（`evidence/reseal.log`）。
- P8 `data/village_v2_p8_seal.json`：frozen 3 件更新（zone.gd、visual.gd、farmland_p8.scn），`reseal_history` 新增 `P13_W3B_LIMITED`（授權、範圍、實測、依賴、反向、證據）。P8 本體的 ART_APPROVED（2026-10-01）狀態不變。
- 下游 1 件：`tools/verify_village_v2_environment.gd` 的 `P12_MEADOW_DRIFT.upstream` 綁了 `farmland_p8.scn` 的位元組雜湊。**先確認** 重烘後同 seed 重算的 MeadowP9 規劃株數 114574、株位摘要 `5d9ef17a…` 都不變（更新前 ENV gate 唯一失敗理由是 `upstream farmland_p8.scn`；更新後 0 失敗，`evidence/env_plan_*_hash_update.log`），才更新雜湊；P9 R5-4 封存的 frozen 1 件隨之更新。
- 子封存追從（只更新雜湊、內容不變）：P9 final、P10 R3b／R3c／R3d／R3e、R4、R4b；每個 seal 的歷史只留 1 筆 `P13_W3B_CHILD_UPDATE`。
- `--seal` 9 條全過（`evidence/seals_after_reseal.log`）：P8（38 檔一致，含「竄改 `village_v2_farmland_lib.gd` 期望雜湊 → 偵測到 1 筆不符」反向）、ENV、P9 FINAL、POP、ACT、CORE、OUTER、HUSE、HUX。

**移除與新增**
- 移除 `CanalSampleP13`：`village_v2.tscn` 的 ext_resource＋node（現在與 `e50c84c^`〔W3 之前〕的 `git diff` 為空）、`scripts_p13/canal_sample.gd`、`tools/village_v2_canal_sample_lib.gd`、`tools/p13/attach_canal_sample.gd`、`tools/p13/shot_w3.gd`（皆可由 `e50c84c` 復原）。外觀來源只剩生成器一處。
- 新增 `tools/verify_village_v2_canal_art.gd`（回歸 tag **CANAL**，`run_village_v2_regression.sh` 加 2 行）：C1 重み非一様、C2 外縁は草、C3 泥水材質、C4a/b/c 木槽の台、C5 口の水幅；永久反向 5 案（uniform／gap／poke／wide／mat），每案只讓自己瞄準的項 FAIL。對**改前**的 `farmland_p8.scn` 執行會 FAIL 7 項（C1×2、C3×2、C4a、C4c、C5），確認 gate 真的區分新舊。

---

## 3. 木槽下暗縫：根因與修正

先把三種可能分開查（`probe_w3b_terrain.gd`、`probe_w3b_branches.gd`）：

| 假說 | 實測 | 結論 |
|---|---|---|
| 木槽與地面真的有間距 | 槽底下面（水面−0.11）到**可見地面**：T0 木槽 3 本各 6.1–21.6／3.3–6.8／3.3–15.3 cm（`evidence/terrain_gap_probe.log`；可見地面＝FarmlandTerrain＋MainTerrain 三角網格射線）。枕木每 1.4 m 一條、順槽向寬 0.12 m（`branch_art` 程式），只佔長度 8.6 % | **是真實間隙** |
| 槽底面或支撐結構露出 | 枕木頂＝槽底下面；側板下緣比槽底下面再低 2 cm（`_trough_seg`）。沒有缺漏的支撐 | 不是 |
| 材質／法線／陰影 | 可見地形與碰撞用 `ground_h` 差最大 12 mm；碰撞本來就是「地面→側板頂」的實心。實體間隙不會因為貼圖／法線而出現；10:00 的光讓槽下縫落在影裡（推論：陰影只是放大它） | 只放大，非成因 |

**修正（最小、貼地、不加遮擋物、不動槽）**：槽下通一條跟著地形的低盛土（`trough_bed()`），把縫實際塞滿。
- 土渠本身就是比地面高約 0.15–0.22 m 的堤，木槽段只是這條堤的延伸。
- 盛土肩高＝水面−0.06（對地面 0.08–0.27 m），自板外面起以 smoothstep 於 0.9 m（自槽中心算）處降回地面。
- 槽下的土面＝水面−0.124，比 collar 渠底（水面−0.12）再低 4 mm（看不見、不 z-fight），在板厚內立起，槽內不出土。
- 竜骨車送り樋側的自由端：肩高自 s＝0.2 m 起、至 1.6 m 才升到全高，避免把土推向送り樋的脚與分水板（量測：脚 4 根、送り樋 Body、DropBox 的 AABB 全在 T0 的 s≤0.2 m 內，`evidence/feeder_legs_probe.log`；P8 `--feeder` 的「竜骨車部材 OBB 內可見網格頂點 0」仍過）。
- 水面高程、坡降、槽、枕木、碰撞、伏越し：等價比對 0 差分（水面 y 最大 0.29 mm）。
- 其他圖層：盛土範圍內有頂點的可見節點 13 個＝P8 自身 10 個（上段水面、竜骨車脚／送り樋／落とし桝）＋3 個 P9 地被平面（`WatersideP9/ww2`、`GroundcoverP9/…/stream_14_0`、`…/MacroVillage/MV_13_2`）；無 props／樹／NPC（`evidence/bed_neighbors_probe.log`）。封存的 P9 層未改，被盛土蓋住的部分不可見；除 §4 的近景外，**未另外檢查這 3 個平面的 z-fighting**。

**修正後的量測（gate `CANAL`，T0 全部木槽取樣點）**
- C4a 槽底下面→盛土頂 **4–20 mm**（最大 14 mm，41 點，不良 0）。
- C4b 槽內（±0.12 m）土比槽底上面低，最小餘裕 **4.5 cm**（不良 0）。
- C4c 板外面的盛土頂不低於側板下端（82 點，不良 0）。
- C5 木槽口的水幅：土渠水面原為 0.6 m 寬、在口直線切斷；現在口前 1 m 內縮到槽內寬度，最大橫向外凸 **0.300 m → 0.174 m**（槽內半寬 0.174）。

**暗部像素量測**（`evidence/dark_gap_before_after.txt`；同鏡位）
- T0 上游 TPS：木構件緊鄰 6 px 內近黑（L<0.05）畫素 **31.2 % → 0.0 %**；14 px 內 28.2 % → 3.2 %。
- T0 下游 TPS：兩者皆 0 %（本來就沒有暗帶）。
- 12 張木槽近景的全畫面近黑畫素平均 1.25 % → 0.73 %；多數下降，`T0_r0_s0_eye` 持平（7.33 % → 7.34 %）——見下。

**殘留（誠實列出）**：T0 木槽頭（竜骨車送り樋側約 1.6 m）仍有暗凹。`T0_r0_s0_eye` 近景的主要暗部在抬高的送り樋下面與樹影（視覺模型判讀），脚與連接段之間的小暗凹前後無明顯差異。這是刻意保留的（理由見上），未用額外遮擋物處理。

---

## 4. N0、T0 各一張代表性 TPS 畫面（同鏡位 Before／After）

撮影條件：正式 `main.tscn` → `village_v2`、Forward+、10:00 固定；玩家 TPS 相機實測距離 8.56 m、離地 3.21–3.23 m、pitch −10.3°（`evidence/camera_params.log`）。pitch 固定 −0.18 rad 並解除滑鼠捕捉（否則實機滑鼠進入視窗時 pitch 會被推到 +31.5°，同鏡位會失真）。重拍同四個鏡位與留存圖比對：平均絕對差 0.65–2.14／765，差>30 的畫素 ≤ 0.8 %，截圖可重現。
目錄 `docs/art_review/village_v2_p13/wave3b/shots/`（`.gitignore` 的 `shots/` 不進版控，與 W1–W3 相同）。

| 畫面 | Before | After | 並排（左 Before｜右 After） |
|---|---|---|---|
| **N0**：玩家 (359,−26) 看 (364,−16) | `before/N0_tps.png` | `after/N0_tps.png` | `compare/N0_tps_before_after.png` |
| **T0 下游**：(336.5,66) 看 (327,57)（兩段木槽與土渠） | `before/T0_down_tps.png` | `after/T0_down_tps.png` | `compare/T0_down_tps_before_after.png` |
| **T0 上游**：(340.5,14) 看 (336,25)（原先全黑） | `before/T0_up_tps.png` | `after/T0_up_tps.png` | `compare/T0_up_tps_before_after.png` |

木槽近景 Before／After：`compare/seam_T0_r2_trough_{s17_low,s4_low,e25_eye,e11_low}_orig_after.png`、`compare/seam_T0_r0_trough_s0_low_orig_after.png`；各接合點 eye／low／top 全套在 `after/seam_*`。

## 5. 農田高視角整體

`after/high_farm.png`（相機 (385,46,14) 看 (346,0,20)，fov 62）；Before `before/high_farm.png`；並排 `compare/high_farm_before_after.png`。

---

## 6. 是否存在新的明顯材質接縫

**數值**（同鏡位、以「土渠／水面／木構件改為不透明洋紅」取精確像素遮罩；`pixel_stats_before_after.txt`、`glare_stats_before_after.txt`）

| 指標 | Before | After |
|---|---|---|
| 土渠平均輝度／周圍地面：T0 下游／N0／農田高視角 | 0.77／0.82／0.72 | 0.84／0.87／0.86 |
| 土渠最暗 5 % 點輝度（T0 下游） | 0.115 | 0.232 |
| 土渠平均 RGB（T0 下游） | (63,69,81) 偏藍灰 | (73,78,67) 灰綠 |
| 水面平均輝度（T0 下游／N0） | 0.387／0.387 | 0.291／0.322 |
| 水面 >0.80 的畫素率，最壞 view（8 方位×2 高度）：T0 下游／N0／T0 上游 | 4.59 %／1.75 %／1.65 % | 0.73 %／0.26 %／0.37 % |
| 水面最高輝度（T0 下游） | 1.000 | 0.953 |

- 「周圍地面」是遮罩外一圈的位置相依量；T0 上游 TPS 因新增的槽下盛土使土渠遮罩面積變 4.3 倍、圈的位置跟著移動，兩邊不可比，故上表不列該 view 的比值。
- 白色高光：**沒有消除，只收斂**。最壞 view（方位索引 6、高 1.5 m）仍有 0.73 % 的水面畫素 >0.80、最亮 0.953；其餘 view 低於此。
- 內坡與渠底設計上就是濕泥，偏暗；這是已批准的方向。

**接縫（誠實列出；視覺判讀為輔助，非美術判定）**
1. **端點接到範圍外仍為黑色濕泥的 P8 渠段**（N0 起點接上段土渠；N0／T0 末端接各塊進水口與支渠）。這些鄰接渠段本輪沒動（未授權），新舊材質在邊界必然存在差異。
   - N0 起點：視覺模型兩次判讀不一致（一次認為出現新的材質階差，一次認為接口與改前相近、改變主要在支線上游）。我**不能確定**，請看 `compare/end_N0_r0_earth_s0_{top,eye}_old_new.png`。
   - N0 末端、T0 末端：Before／After 並排，直線切口與三角黑楔在兩邊**同位置都有**（改前就有的舊幾何）；After 只是周圍黑區縮小，端點形狀本身沒修（`compare/end_N0_r4_earth_e7_top_old_new.png`、`end_T0_r2_earth_e37_top_old_new.png`）。這不是本輪造成，也沒有被修。
2. N0／T0 內部：外縁固定為草，TPS 三張與高視角在視覺判讀中未見「土色帶在草上直線收邊」。
3. 其他殘留：
   - N0 平面有 4 個折點，各轉 42°–45°（T0 已被 R2D-Fix 圓角化，最大 12°；`evidence/branch_corners.log`）；屬水路平面，未動。
   - T0 上游 TPS：視覺模型仍描述「槽下方較暗、有直線段與接頭」。量測上槽緊鄰的近黑畫素已降到 0 %（§3），剩下的暗部我沒有逐像素定位（可能是樹影與木槽自身陰影面）。
   - T0 木槽頭的暗凹（§3）。

---

## 7. Git 與未解決事項

**Git**：本地 commit，**不 push**；只含本輪檔案，用暫存 index 提交，原本 staged 的 53 項與其他 session 的未提交修改未動（commit hash 見最終回報，其父為 `e50c84c`）。`farmland_p8.scn` 走 LFS（`.gitattributes`），本地 commit 只存指標與 `.git/lfs` 物件。

**實際執行的測試（對象都是本次 commit 的最終版本）**

| 範圍 | 結果 | 證據 |
|---|---|---|
| P8 正式重烘＋ P8 gate | 0 失敗（田 7+67、水位誤差 0.0000 m） | `p8_build.log`、`p8_gate_and_negatives.log` |
| P8 反向：`--negative`、`--negative-branch`、`--negative-feedcut` | 3 案都正確偵測／FAIL | 同上 |
| 逐節點等價比對 | PASS（見 §2） | `p8_equivalence.log` |
| 新 gate CANAL | 0 失敗；反向 5/5（含基準場景全 PASS）；對舊場景 7 項 FAIL | `canal_gate*.log` |
| P8 農田擺放稽核 | bund 23160／水 666 取樣，0 失敗 | `farm_place.log` |
| P8 `--feeder`／`--feeder-negative` | 0 失敗（含 1620 個相機姿勢）／反向 3/3 | `feeder*.log` |
| 一次代表性 TPS 通行（`tools/p11r2d/walk_branches.gd`，玩家實際 CharacterBody3D 輸入） | 6 段全部抵達、橫偏 0.00 m、停止 0 幀；N0 土渠直角橫越時足元−地面最大 0.22 m（＝堤頂高上限 0.15+0.07）；NPC 通路與新支線碰撞 0.5 m 內 0 件；道路面干涉 0；伏越し 3 處水頭差皆為正 | `branch_walk.log` |
| 封存依賴 | 9 條 `--seal` 全過；ENV plan gate 0 失敗；MDW plan 0 失敗；GC plan 0 失敗 | `seals_after_reseal.log`、`env_plan_after_hash_update.log`、`mdw_plan.log`、`gc_plan.log` |
| MultiMesh 烘焙稽核（非 headless） | `farmland_p8.scn` 1844 節點／824066 實例，零矩陣 0；全場景 0 項失敗 | `mmbake.log` |
| ASSET、PLACE | ASSET 0 失敗；PLACE 207／REVIEW 0／FAIL 0＋selftest 0 不符 | `asset.log`、`place.log` |

**未跑（依指示，或本輪未涉及）**：完整回歸、全村實走、P8 `--zone` 25 段與 `--cost`／GPU A/B（P8 多了 1580 三角形，未量 GPU 成本）、水車供水流程（未改水利）。因此我**不聲稱**其他 gate 在本輪之後仍全綠，只聲稱上表有跑的那些。

**未解決／待你決定**
1. **範圍外的黑色渠段**：P8 其他全幅濕泥的 ribbon（上段土渠、各塊 `LateralBed`／`MainBed`／`DrainBed`、逐階水路、排水口）仍是黑岸，與 N0／T0 端點形成材質邊界（§6-1）。是否把同一套漸變延伸過去需要你授權（會再動 P8 生成器並再一次 limited reseal）。
2. T0 木槽頭（竜骨車送り樋側）的暗凹：刻意保留；若要處理需要動送り樋附近，等你決定。
3. N0 的 42°–45° 折點、端點的舊黑楔：屬水路平面／舊幾何，未動。
4. 槽下盛土是新增幾何（不可走、無碰撞）；你若判定不要，回退即可。
5. 暫存備份 `godot/.godot/w3b_backup/`（舊 `farmland_p8.scn` 等，git 忽略）仍在，供 `p8_equivalence_w3b.gd`、`shot_w3b.gd old` 使用；驗收後可刪。

證據目錄：`docs/art_review/village_v2_p13/wave3b/evidence/`；工具：`godot/tools/p13/*w3b*`、`godot/tools/verify_village_v2_canal_art.gd`。
