# P13 W9 Phase 7 — MCP-first 3D 製作試行（MKT_017・MKT_018）ART_REVIEW

日期：2026-10-16　狀態：**ART_REVIEW（未 ART_APPROVED、未封存、未 push）**　依據：使用者「P13 W9 — Transition to MCP-First 3D Production」。
Phase 6（019／021／022／003）仍在 ART_REVIEW，幾何未動；已核准的 Phase 3–5、P10 封存內容、`village_v2.tscn`、相機／控制器、`assets/blender/sources/` 都沒有改。

## 1. MCP 連線與能力（實際呼叫，細節見 `evidence/mcp_tool_log.md`）

| | 能做到（實測） | 不能／沒做 |
|---|---|---|
| **Godot AI MCP**（4.2.1、editor PID 12976） | 讀 editor 狀態、分頁、節點、屬性、metadata、碰撞 shape、資源（.res ArrayMesh）、editor 截圖；`project_run`（custom、autosave=false）＋`game_manage` 讀**執行中遊戲**的節點樹／屬性 | 讀不到分頁 dirty 狀態。editor 記憶體中的 overlay 是舊版（40 棟，沒有 Phase 6 的 4 棟）→ 依規則不 reload、不存。另有人在用 editor（plugin 紀錄裡有非本 session 的 `trail.tscn` 切換、beast_path 腳本錯誤）→ **全程 R0（唯讀），沒有任何 editor 寫入／存檔**，W1 隔離場景也沒建 |
| **Blender MCP**（Blender 5.2.1 PID 17148） | `execute_blender_code`：在 live Blender 載入既有 builder 函式庫、匯入 Godot 實景、重建 2 棟（0.4–0.6 s）、BVH 交差檢查、量距離；`look` 多角度截圖 | `get_addon_status` handshake 失敗（protocol null），其餘呼叫正常。`look` 的 material／rendered 光線和遊戲不同，不能判斷材質明暗 |

**工作流程（本回實際用法）**：Godot MCP 讀現況 → headless 把 017／018 周圍 26 m 的實景網格匯出 GLB → Blender MCP 在 live Blender 裡用同一套 builder 函式試作、看形、量交差 → 定稿寫進 `build_w9p7_arch.py`（正本）→ 既有的決定論 pipeline（Blender `-b` → prefab → bake）→ Godot（headless gate＋實機 TPS 截圖＋MCP 讀執行中遊戲）。Blender live 狀態只是試作場；結束時已清掉 P7 物件並恢復場景相機。

## 2. 選定（4 候選 → 2 棟）

Phase 6 最終的正常 TPS 24 視點 ID pass，候選畫面佔比合計：**018 77.3 %、017 58.0 %**、002 35.3 %、007 26.9 %（`evidence/candidates_coverage_before.txt`）。vision 也判 017 跟對面的 002 幾乎是鏡像的平入二階。

- **017 酒屋**（南入口西側）：兩側 2 m 內沒有建築，兩面山牆都露在外面；它和 002 正好是「進村第一眼」看到的一對。只要改 017，鏡像就解除了。
- **018 住宅**（井戶廣場角落）：南面山牆整面朝向廣場，北上時佔畫面 7–18 %，但讀起來只是一大片無變化的牆。
- 002 不動，因為 017 改了鏡像就已解除。007 除了 S100（15 %）之外畫面佔比都小，所以不選。（vision 原本把 007 排第一，但量測不支持。）

## 3. 各棟（`assets/blender/village_v2/build_w9p7_arch.py`）

| 棟 | 新型 | Before → After | 三角面 L0 |
|---|---|---|---|
| **017 酒屋** | **本卯建の造り酒屋**：壁 5.6 m、勾配 0.55 切妻平入（棟 8.35 m，比對面 002 高 0.9 m）。兩端山牆各有一道本卯建：高出屋面 0.95 m、比妻面外凸 0.28 m、瓦笠向兩側各挑出 0.12 m，笠的軒端有小鬼瓦，棟上有合掌塊。山牆上半部改成一整片外凸 0.07 m 的白漆喰塗籠（蓋住 Kit 原本的束與貫），加蔵窓 2、水切り瓦、焼杉腰板。二樓正面是塗籠配虫籠窓 3，一樓是酒格子＋戸口（同 Kit 位置）＋店台，外加出 0.80 m 的瓦下屋（x ≤ 2.12，以袖卯建收尾）| 平入二階 7.65（Kit 實頂 7.27）→ **棟 8.35・卯建頂 9.4** | Kit 10,729（52 網格）→ **12,342（1 網格・4 材質）** |
| **018 住宅** | **表低奥高的非對稱切妻**：棟往後移 1.0 m（棟 6.85 m）。正面是厨子二階（壁 4.05 m，軒出 0.60），後半是本二階（壁 5.35 m），所以從廣場看山牆是左右不對稱的五角形。山牆為真壁：柱 5、胴差、梁。一樓有格子 2 間＋勝手口，後段二樓有出格子＋小窓，前段二樓（屋根裏）有小窓 2，臨街角落加焼杉腰板。+x（019 側）螻羽只出 0.06 m，−x（廣場側）出 0.30 m。正面開間同 Kit：格子・戸口・格子，二樓為土壁粗格子的虫籠窓，只在戸口上加板の霧除け | 厨子二階・左右對稱（Kit 實頂 6.36）→ **非對稱，棟 6.85** | Kit 12,848（54 網格）→ **13,778（1 網格・4 材質）** |

**設計前量好的 AABB 限制**（`evidence/aabb_constraints.txt`，用 gate 同一組 `others_for` 箱）：
- **017**
  - W9 杉玉箱：x 1.17–2.30、y 2.24–3.26、z 4.98–6.42。P10 酒の幟：x 2.25–2.88、y ≤ 3.79、離牆 0.53 m。
  - 據此把下屋放在牆際 4.05 m，桁下端約 3.45 m。r1 放在 3.80 m 時，在 Blender 實測與杉玉吊り木交差 16 處，所以抬高。下屋止於 x ≤ 2.12 避開幟，袖卯建深 ≤ 0.50 m。
- **018**
  - 和 019 牆距 0.204 m，019 螻羽外出 0.08 m，所以 018 的 +x 螻羽只出 0.06 m。
  - 井戶離牆 1.85 m（y ≤ 2.25），P10 桶山 y ≤ 1.28。

**整合 rule 的修正（實測後才發現）**：MCP 讀執行中遊戲時看到 017 的杉玉 `visible=false`。原因是 `arch_w9r2.gd` 的 R1_HANG 規則：凡是改建成 overlay 的建築，牆上掛的 R1 物件一律隱藏。這會讓酒屋的招牌「杉玉」消失。
- 修法：在 `w9r2_lib.gd` 的 SPECS 新增資料欄位 `keep_r1`，017 設為 `["sugi"]`；`build_w9r2.gd` 把它寫進 meta，`arch_w9r2.gd` 遇到列在 `keep_r1` 的種類就不隱藏，verifier 的預期件數也扣掉保留項。
- 017 加了一塊吊り木の受け板（y 3.27–3.42，在 gate 箱上緣 3.26 之上）。原因：Blender 實測吊り木端離新牆 0.060 m，沒有它杉玉會懸空。
- 效果：其他 45 棟行為不變（R1 隱藏件數 10 → 9，少的就是這一顆杉玉）。

## 4. 實際檢查結果

| 檢查 | 結果 | 證據 |
|---|---|---|
| 建築 overlay gate `verify_w9r2.gd`（46 棟） | **621 PASS／0 FAIL**，反向案例 36/36。涵蓋：構造、戸口前、頭上帶、張り出し、屋根の収め、P10／R1 物件貫入（017 的 6 件含杉玉，貫入 0）、鄰棟 massing、LOD、可逆 toggle、R1 隱藏 9 件 | `evidence/verify_w9r2_excerpt.txt` |
| 018 與 019（Phase 6）實網格三角形交差 | **0**（雙向；換回原 Kit 018 也是 0） | `evidence/mesh_intersection_018_019.txt` |
| Blender MCP BVH（新棟對實景 687 網格） | 017：只有受け板與吊り木相交 11 處（刻意設計）；對酒の幟 0。018：0 | `evidence/mcp_tool_log.md` |
| 正常 TPS 相機 | Before／After 24/24 座標完全一致，代表碰撞與 SpringArm 沒變；24 個相機都不在新棟可見體積 ±0.3 m 內 | `evidence/tps_id_coverage.txt` |
| 碰撞／入口 | body 碰撞、footprint、戸口位置都沒動，overlay 不加碰撞。因此**沒跑真實步行**（沒有可走的東西改變） | — |
| 擺放（placement audit `--selftest`） | 017／018 不在 REVIEW／FAIL 名單裡。但 audit 本身不乾淨：PASS 201／REVIEW 4／FAIL 2，selftest 有 2 項不符。涉及 MXC_007/008、RSW_074/075、MKT_029/030 的 body 碰撞，和 aabbfp 案例，**本回都沒碰過，是既有狀況，未調查** → 登記 #27 | `evidence/placement_audit_excerpt.txt` |
| 效能（代表值） | 46 棟 LOD0 690,448／上限 715,300（15,550 × 棟數，公式沒改），新 2 棟平均 13,060 < 15,550。網格數：Kit 106 個 → overlay 2 個（各 4 材質）。**沒有量 frame time** | — |
| MCP 讀執行中遊戲 | 新 L0 已載入、可見、材質已校色；Kit 構件隱藏；杉玉在 r2 後會顯示（verifier 確認 R1 隱藏件數＝9） | `evidence/mcp_tool_log.md` |
| 原有 53 個 staged 項目 | 與 baseline（`git diff --cached --raw`，含 mode／blob）逐 byte 相同 | — |

## 5. 看得到的改善（正常 TPS，相機一致）

vision 評分（Before → After，1–5）：
- **017 的辨識度**：N008、N020、N032、F002、F017 由 1–2 升到 4，S040 由 1 升到 3。卯建在中距離（N020／F002／F017）看得出是凸起的防火牆，遠距離仍會縮成一圈粗山牆線。
- **018 的辨識度**：N058、F019 由 2 升到 4，N046 由 1 升到 3，N066／F003 由 2 升到 3。N074 看不到山牆，沒有改善。

畫面佔比（ID pass）：017 合計 58.0 % → 68.5 %（N020 11.8 → 15.1 %、F002 13.7 → 16.4 %）。018 合計 77.3 % → 77.5 %，面積幾乎不變，改變的是輪廓與立面組成。

審圖用：
- `review/A_MKT017_before_after.jpg`、`review/B_MKT018_before_after.jpg`（最終版）
- `review/R_iteration_r1_*.jpg`（r1）
- `review/M_blender_mcp_*.png`（Blender MCP 試作畫面）
- `review/S0／S1`（選定時的 TPS 畫面與 Godot MCP editor 截圖）

## 6. 已知缺陷（判斷待決）

1. **017 山牆大片白牆、開口很小**：vision 每一輪都提。正面看時卯建與山牆合成一圈粗框；遠景（N008／S040）卯建看不出來。
2. **017 一樓店面在陰影中幾乎全黑**，跟其他棟一樣，屬全域照明問題，本回未處理。
3. **018 後半（本二階）讀起來不夠像一層完整樓**；廣場側仍有大片漆喰；街側正面在軒影下是一條暗帶；和 019 的交界在畫面上很擠（實測交差為 0）。
4. **018 的優點只在 N058／F019 兩個角度看得到**，從街內（N074）看不到山牆。
5. **上層無碰撞（同 #22／#23／#25 類型）**：017 碰撞頂 5.40 m，新壁 5.6 m＋屋根＋卯建；018 碰撞頂 3.90 m，後牆 5.35 m。預設 TPS 相機在牆邊約 3.22 m 高，碰不到 017 的庇桁（≈ 3.45 m）和 018 的垂木尻（≈ 3.46 m）；但玩家調高俯仰時可能進入上層。**未取樣** → 登記 #26。
6. 017 山牆的 Kit 鬼瓦和螻羽被卯建包在裡面（不可見，gate 的 meta 照樣記為有鬼瓦）。棟端實際上是由卯建的合掌塊收頭。

迭代：每棟 r1 → r2，**兩輪都用完**，依規定停止，未進 r3。
- 017 r2：卯建加厚、加高、外凸，山牆一片化，下屋縮淺。
- 018 r2：軒出 0.75 → 0.60，加 1 間格子、2 個窓。
- 另加杉玉的 keep_r1 與受け板（不算美術迭代）。

## 7. 檔案

- **新增**：`godot/assets/blender/village_v2/build_w9p7_arch.py`、`godot/assets/village_v2/w9r2_arch/mesh/B_P_MKT_{017,018}_L{0,1}.res`
- **修改**：
  - `build_w9r2_arch.py`：exec P7，+3 行
  - `tools/p13/w9/w9r2_lib.gd`：SPECS 加 2 棟，新增 `keep_r1`
  - `tools/p13/w9/build_w9r2.gd`：寫入 meta，+1 行
  - `maps/village_v2/scripts_p13/arch_w9r2.gd`：遵守 keep_r1
  - `tools/p13/w9/verify_w9r2.gd`：預期件數扣除 keep_r1
  - 重新生成的產物：`w9r2_arch.glb`、`modules_blender.json`、`w9r2_arch_manifest.json`、`maps/village_v2/gen/arch_w9r2_p13.scn`
- **未 push**。
