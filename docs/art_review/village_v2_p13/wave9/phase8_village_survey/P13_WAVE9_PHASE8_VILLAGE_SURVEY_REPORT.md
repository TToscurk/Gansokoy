# P13 W9 Phase 8｜人間之里 全村完成度調查＋第一批有限改善（ART_REVIEW）

> **狀態：ART_REVIEW（未核准、未封存、未 push）。** 本文件不是美術核准；gate PASS 與 AI vision 分數都不是美術品質的證明。
> **第一批 overlay `EnrichW9P8` 已生成但「尚未掛進 `village_v2.tscn`」**——共享 Godot 編輯器此刻開著 `village_v2.tscn`，無法確認它有沒有未存檔的修改，所以依指令不寫共享場景（§8、§10）。所有 AFTER 圖與檢查都是在獨立行程中把 overlay「記憶體內掛載」得到的。正式進遊戲需要使用者授權掛載（3 行）。
> Phase 7 的 MKT_017／018 依使用者指示視為現行視覺基準，本輪未動；Phase 6 四棟仍在 ART_REVIEW，未動。

## 0. 結論

1. 全村 187 棟 Kit 建築全部有可見的正式 Kit 外觀；**沒有「遠景灰盒建築群」**。真正的灰盒／佔位只有 5 類（§3），其中玩家最容易看到的是**丘腳社寺的 18×12×9 m 方塊**與**除錯層（浮空地名 39 個、地區輪廓線 7 條、任務錨點圓柱 8 根）**。
2. 除錯層在 ReviewStart（審圖起點）會被隱藏，但**不經 ReviewStart 的載入路徑全部可見**（`--map=village_v2`、獸道 `beast_path` 南端 portal → village_v2）。這是 V2 成為正式人間之里之前必須處理的第一順位問題，改法很便宜，但要動 `main.gd` 或生成器／主場景，需授權（§5 #1）。
3. 第一批做了兩區：**A8 稗田邸西側的接近路**、**B8 東北聚落（香霖堂口）**。154 個構件全部是既有資產的再配置（沒有新網格、沒有 MultiMesh），可整層拿掉。近距離 TPS 的生活感有改善，遠距與 B8 整體仍弱（vision 懷疑式評估：「近處可信但收斂的改善」「整體仍不是有人住的聚落」）——**改善幅度有限，請使用者判斷是否值得掛載**。

## 1. 方法與安全

| 項目 | 實際做法 |
|---|---|
| JEV（任務前） | 本輪新寫 25 案的契約測試，在任何場景讀寫前執行：**24／25 符合**（T21 判得比預期更保守）。`evidence/jev_p8_summary.md` |
| 場景 hierarchy | Godot MCP 唯讀（`session_manage list`／`editor_state`／`node_manage get_children`／`node_get_properties`／plugin log）＋ headless 唯讀盤點 `repro/inventory.gd`（root 37、建築 196、地標 15、PrimitiveMesh 群 15、具名 placeholder 2） |
| 共享編輯器 | 實際連線對象：Godot 4.7.2、專案 Gansokoy、current_scene `res://maps/village_v2/village_v2.tscn`、未播放。**本輪沒有在共享編輯器切場景、播放、存檔或結束任何行程**；所有寫入都在 repo 的生成器原始碼與獨立 Godot 行程 |
| 截圖 | 獨立的圖形 Godot 行程（非 headless、非共享編輯器）、正式玩家＋實際 SpringArm、10:00；scratch 的拍攝 harness `repro/p8_shots.gd`（由 `w7_shots.gd` 複製，原檔未改；加 `--show`、`--mount`） |
| 俯瞰 | 5 張，只作診斷；評估以 52 個地面 TPS 視點為主 |
| Git | 原 53 個 staged 項目逐 byte 比對 `SAME_53`（`diff --cached --raw --no-abbrev`）；只提交本任務的檔案，不 push |

## 2. 全村完成度評估（玩家視角）

依據：52 個正常 TPS 視點（`review/S1–S5`）的直接審圖＋ID pass（`evidence/survey_free_space.txt`）。分數是 vision 模型的懷疑式意見（1–5），只作方向參考（`evidence/vision_notes.md`）。

| 區域 | 完成度與問題（實際看到的） | 生活感 |
|---|---|---|
| 主街（E01–M06、L02–L04） | 建築最完整（W9 已改建 46 棟大多在此）。南段 M01 路口大片裸地、物件看不出用途；s≈110–178 m 仍重複（登記 #17） | 2–3 |
| 次街・中橫街（X01–X03、Y01–Y03） | X03 中橫街東端→稗田邸：長而空的接近路、白塀單調（→ A8） | 1–2 |
| 住宅・窄巷（W01–W10、N01–N03） | 西巷 Phase 3／4 已改善；W10 南巷東段、W01 北段有大片未整理地面；N 系列（丘腳西）幾乎沒有人的痕跡 | 1–2 |
| 東北聚落（D02–D04、C05） | RNE 19 棟在 W9 完全沒動過；門前空、屋頂連續同一 Kit；龍神橋過來第一眼就是這裡（→ B8） | 1–2 |
| 市集・路口・公共場所 | 市集廣場（P10）完成度高；火見櫓前、鈴奈庵前已有 P9／P10 封存的庭 | 2–3 |
| 農地・農家（F01–F05、K01） | P8 田封存、FarmsteadP13 已改善；田埂筆直、路肩寬而單調（F04／F05） | 2 |
| 河岸・橋・水車・水渠（C01–C05） | 水車 3 座完成；**西渠 B7、水車旁 F7 兩根藍色圓柱 placeholder**（#9，本輪不改） | 2 |
| 出入口・地標過渡（E01–E03、H01–H04） | 南大鳥居→村內的過渡由 P9 封存林構成，路與草帶一路重複；丘腳街北望正中是**丘腳社寺灰盒** | 1–2 |
| 遠景 | `EdgeClosureP10`（VistaCanopy 等）是有意的遠景封邊；沒有遠景灰屋 | — |

鏡位本身的問題（非村子缺陷）：H01、D04 的鏡位被前景屋簷佔滿；C04 右下黑楔是相機貼近 RSW_077 的陰影牆。

## 3. 灰盒／未完成 placeholder 盤點

| # | 位置・節點 | 擁有者／狀態 | 玩家可見／可達 | 判斷 | 建議 |
|---|---|---|---|---|---|
| G1 | **丘腳社寺** `Landmarks/LANDMARK_HILLFOOT_TEMPLE/Block`（BoxMesh 18×9×12 m，中心 (228, −170)） | P4 灰盒；TASK E 方向案（`wave9/TASK_E_hillfoot_temple.md`）等待使用者決定造型 | 可見（丘腳街北望正中、俯瞰 A4）；丘腳街路緣約 12 m，可走到 | **未完成的可玩地標**，不是遠景 proxy | **replace**——需先由使用者決定方向（TASK E），本輪不動 |
| G2 | **除錯層** `Debug`（Label3D 39、`DistrictOutlines` 7 條）＋`QuestAnchors`（CylinderMesh 8 根，0.5×2.6 m） | 生成器 `gen_village_v2.gd` 的開發用層；只有 `review_start.gd`／`p13_preview_boot.gd` 會隱藏 | 不經 ReviewStart 的載入路徑全部可見（`evidence/debug_visibility_normal_flow.txt`、`review/D_debug_layer_normal_flow.jpg`：巨大「LANDMARK_SOUTH_GATE」「鈴奈庵（候補）」「跌水（placeholder）」字樣與洋紅色柱） | **開發用疊層外露** | **hide in normal flow**（保留給開發用）；需授權（§5 #1） |
| G3 | `Water/Waterfalls/WATERFALL_B7`／`F7/Placeholder`（CylinderMesh 1.2×3.0 m） | P2 佔位；登記 #9 待處理 | 可見（C04、C 區）；無碰撞 | 未完成佔位 | **defer**（使用者明令未授權前不改 P8 水體） |
| G4 | 附屬小屋・藏 9 棟 `S_A_MKT_002／006`、`S_A_RSW_002／006／010／014／018`、`S_A_RNE_002／006` | P4 灰盒的 mesh 全部 `visible=false`、碰撞 disabled、`retired_by_hero=true` | 灰盒不可見；由 Hero 小屋／藏取代 | 已被取代 | **retain**（不需處理） |
| G5 | `FarmsteadP13/A1_noka`、`A2_naya`（BoxMesh 101 個組成的農家） | Wave 2 的正式農家（`wave2/P13_WAVE2_REPORT.md` §4），W9 R1 已加庭先 | 可見、可達 | 刻意用基本形組成的正式建築，不是灰盒 | **retain** |
| G6 | `Districts/FarmlandEast/FarmlandP8`（BoxMesh 115：堰柱等小構件） | P8 封存 | 可見 | 正式細部 | **retain** |
| G7 | `EdgeClosureP10`（村外封邊樹冠・遠景） | P10 R5c 封存 | 遠景 | 有意的遠景 proxy | **retain** |

## 4. 位置索引與注記地圖

`review/village_map_p8.png`（俯瞰資料圖、診斷用）：地區、道路、水、建物的 W9 改建狀態、灰盒 G1、任務錨點、portal、52 個 TPS 視點、本批 A8／B8、前五名與延後項目。

| 代號 | 世界座標 (x, z) | 內容 |
|---|---|---|
| ① 除錯層 | 全村（39 個浮空字、7 條輪廓、8 根錨點柱） | §3 G2 |
| ② 丘腳社寺 | (228, −170)；視點 H01 (212, −148)、H04 (298, −140) | §3 G1 |
| ③ A8 稗田邸西 | (364..385, −54..−9)；視點 X03 (345, −35)、K01 (392, 14)、PA1–PA4 | 本批 |
| ④ B8 東北聚落 | (420..502, −252..−176)；視點 D02 (384, −205)、D03 (436, −215)、D04 (470, −197)、PB1–PB4 | 本批 |
| ⑤ 主街南段路口・火見櫓前 | M01 (240, 52)、L02 (241, 55) | 封存／核准層內（市集 AuxYards、TowerYard、霧雨店 Hero） |
| D1 南入口道路兩側 | E01–E03 (222..231, 118..200) | P9 封存林＋獸道銜接 |
| D2 南巷內側空地 | W10 (185, 89)、W04 (207, 40) | P9 地被／校庭 |
| D3 田埂路肩 | F04 (440, 100)、F05 (500, −60) | P8 封存田 |
| D4 水渠護岸的重複感 | C01–C03 | 封存層 |
| D5 寺子屋南側 | L01 (213, 24) | P9 R4-3 校庭（封存） |
| B7／F7 | (142.8, 42)、(307, 70) | #9 |

## 5. 五個高影響改善機會（排序）

評分：可見度・未完成的嚴重度・村落身分／日常感・探索價值・成本與回歸風險。

| 排名 | 機會 | 理由 | 成本／風險 | 本輪 |
|---|---|---|---|---|
| **1** | **非 ReviewStart 載入時隱藏除錯層**（Debug＋QuestAnchors） | 一出現就是全畫面的開發文字與洋紅柱（3／4 鏡位 vision 判「severe」）；全村性 | 極低（載入後把 2 個節點設不可見即可）；但要改 `main.gd`、`gen_village_v2.gd` 或主場景，且獸道 portal 正由另一 session 開發 → **需授權與協調**。註：目前正式開局 `trail → slice` 還沒接到 V2，所以今天的正式流程看不到；V2 正式化或獸道 portal 開通時就會外露 | 未做（需授權） |
| **2** | **丘腳社寺灰盒的替換** | 丘腳街北望正中、可走到的未完成地標；神社參道的過渡被它打斷 | 中～高（新建築）；造型方向待 TASK E 裁定 | 未做（需方向裁定） |
| **3** | **A8 稗田邸西側的接近路**（阿求的任務路線：中橫街→田埂道→大宅門） | 任務必經、長而空、白塀單調；空地不屬任何封存層 | 低（可逆 overlay） | **已做** |
| **4** | **B8 東北聚落・香霖堂口** | W9 完全沒動過的 19 棟；過龍神橋第一眼、香霖堂任務出入口 | 低（可逆 overlay） | **已做** |
| **5** | **主街南段路口（M01）・火見櫓前（L02）** | 正常 TPS 很常經過；裸地與看不出用途的散置物 | 中：可見空地屬 P10／P9 封存或已核准的構成，要動就得先開封存範圍 | 未做（需範圍裁定） |

## 6. 第一批實作（A8、B8）

原始碼：`godot/tools/p13/w9/w9p8_lib.gd`（計畫）＋ `build_w9p8.gd`（plan／bake；由 `build_w9p4.gd` 派生）＋ `verify_w9p8.gd`（gate）。產物：`godot/maps/village_v2/gen/enrich_w9p8.scn`（24 KB）。
沿用 W9 R1／Phase 3／4 的 `W9.why`（道・建物・戸口・水・田・封存物・NPC 動線・Hero 不侵入）與接地規則；固定 seed，plan 兩次逐項相同（`PLAN_DETERMINISTIC`，154＝154）。

| 區 | 群 | 內容 | 件數 |
|---|---|---|---|
| A8 | `A8_jizo` | 中橫街東端與田埂道的辻：地藏與供花 | 4 |
| A8 | `A8_rice_yard` | 西塀外的稻置場：荷車沿塀停放＋俵、稻叢；筵上的臼與背負籠、鋤（全部 < 2 m，不遮塀與屋敷） | 9 |
| A8 | `A8_wall_foot` | 西塀腳：躑躅・低木・笹・羊齒的不規則群＋若木 2 | 14 |
| A8 | `A8_north_grove` | 中橫街終點北側空地：屋敷林邊緣的雜木（高木 3，其中 ≥ 8 m 的 2）＋中層 4＋低層 12 | 19 |
| B8 | `BH_RNE_*` ×11 戶 | 各戶門前：水甕、薪、鉢、朝顏、簾、暖簾、吊柿／辣椒、籠、農具（同一組合不用在 3 戶以上） | 24 |
| B8 | `BG_RNE_*` ×8 宅間 | 垣・下屋（薪／農具）・小祠・木戶（木戶退到宅間深處 5.5 m） | 60 |
| B8 | `B8_well` | 香霖堂口北側空地的共同井戶＋手桶・水甕・草 | 5 |
| B8 | `B8_canopy` | 屋頂並列背後的樹冠（高 ≥ 8 m 的樹 6 棵），打斷同一 Kit 屋頂的連續 | 19 |

- 計 **154 件**（A8 46、B8 108）、25 群、45 種；既有 Kit／veg 105 件＋W9 R1 的 W9 kit（已用於已核准的 Phase 3／4）49 件。**沒有新網格**、沒有 MultiMesh。
- MeshInstance 388、碰撞箱 57、LOD0 107,269 tri。
- **r1 → r2（一次有理由的修正）**：r1 gate 3 項 FAIL（井戶的碰撞在巷的分岔口造成 SpringArm 重度縮短 116 件、木戶 25 件；宅間判定把 13.6 m 的巷分岔當成宅間，垣與若木壓到路緣；B8 背景高木不足），vision 也指出 PA2 相機進葉子、稻置場「散落的小點」、孤立的長幹赤松。r2：井戶移到巷西空地（離巷軸約 6 m）、木戶退後 5.5 m、宅間上限 9 m、雜木林高木退到相機帶外、稻置場收成兩組、赤松換成樹冠大的小楢並補 2 棵高木。gate 歷史：`evidence/GATE_HISTORY.txt`。

## 7. BEFORE／AFTER（正常 TPS、同一鏡位）

- `review/A_hieda_west_before_after.jpg`（X03、K01、PA1–PA4）、`review/B_ne_hamlet_before_after.jpg`（D02–D04、PB1–PB4）。r1 的 AFTER 在 `review/R_iteration_r1_*.jpg`。
- 13 鏡位的相機座標 BEFORE／AFTER 最大差 **0.0 m**（讀自兩次拍攝的 index.json）。鏡位清單：`evidence/at_ba.txt`。
- EnrichW9P8 在 AFTER 畫面的佔比（ID pass，`evidence/p8_coverage.txt`）：A8 0.8–7.1 %、B8 0.3–10.2 %；D02 0.8 %、D04 0.3 % 幾乎看不出差異。
- vision 懷疑式評估（線索，非裁定）：A8 X03 2→3、K01 2→2、PA1 1→3、PA2 1→3、PA3 2→3、PA4 1→3；B8 D02 2→2、D03 2→3、D04 2→2、PB1 2→3、PB2 2→2、PB3 2→3、PB4 2→3。同一張 BEFORE 在 r1／r2 兩次評分差到 1–3 分，分數本身會漂移。

## 8. 驗證（與改動成比例）

| 項目 | 結果 | 出處 |
|---|---|---|
| 場景載入・資產完整 | bake 後以 `CACHE_MODE_IGNORE` 回讀：構件 154＝計畫 154、MeshInstance 388、碰撞 57、MultiMesh 0 | `evidence/build_final.txt` |
| gate `verify_w9p8.gd`（headless、記憶體掛載） | **42 PASS／0 FAIL**（含反向案例：路面上的樹、建物中的小屋、浮空 0.6 m、戶口碰撞、二重掛載、等間距、portal 6 m、SpringArm 注入箱都能被抓到） | `evidence/gate_final.txt` |
| 碰撞・通行 | 154 件全部不碰道路・建物・戶口・水・田・封存物・NPC 巡回路・Hero，且接地；樹木不壓路緣 0.6 m、高木離路緣 ≥ 3 m；碰撞箱 57 個不碰戶口空帶與 NPC 巡回路；任務出入口（香霖堂・稗田邸 portal、阿求 anchor）最近 6.1 m | 同上 |
| 導航 | 村內**沒有 NavigationRegion3D**（NPC 走固定巡回路徑）；巡回路徑上 0.35 m 內無新碰撞 | 同上；`village_v2.tscn` 搜尋 |
| 相機（SpringArm） | 4 條通行帶 29,040 樣本（軸 ±1.2 m、16 方位）：重度縮短（≥ 2.0 m 且腕 < 3.0 m）**0**；≥ 0.30 m 的縮短 3 件；最差 7.50→3.43 m（B8 東北巷 (462.1, −236.9)） | 同上 |
| 可逆性 | 單一 root overlay；`visible=false` 時 388 個 mesh 全部不顯示；拿掉後 root 節點構成與掛載前相同。掛載本身是 `village_v2.tscn` 的 3 行（ext_resource、空行、node；`build_w9p8.gd -- --attach`），刪掉即還原 | 同上 |
| 封存內容 | 所有 `godot/data/village_v2_*seal.json` 頂層 `frozen` 表 1,155 項 sha256 全部一致（其中幾個 P10 seal JSON 有別的 session 未提交的修改，本輪未碰）、本輪新檔不在其中；`village_v2.tscn` 未修改；原 53 staged `SAME_53` | `evidence/seal_check.txt` |
| 效能（1600×900、Forward+、vsync off、10:00、ON／OFF 交替各 2 輪×100 幀） | Δframe +0.14～+0.33 ms、ΔGPU +0.11～+0.22 ms、Δdraw calls +86～+222、Δprimitives +5.4 萬～+15.0 萬（ON 時 frame 10.1–11.8 ms） | `evidence/perf_p8.txt`／`perf_p8.json` |

**沒做的**：真玩家控制器實走（只用 ray 掃描）、共享編輯器中的掛載狀態 runtime、全回歸（隔離的視覺 overlay，依指令不跑）、MMBAKE（沒有 MultiMesh，不適用）。

## 9. 已知限制（不再反覆打磨）

1. **未掛載**：overlay 不在 `village_v2.tscn`，正式載入看不到。
2. A8：遠距（X03、K01）只看得到一團綠；稻置場的小道具仍顯零碎；PA2／PA4 畫面下緣有近景葉子（相機不在葉子裡，SpringArm 掃描 0 重度）。
3. B8：vision 判「整體仍不是有人住的聚落」；PB2 沿路仍是空牆與空地；井戶周圍淺色石材與舊木屋不太搭；吊柿排得太規則；PB3 的竹垣片顯得孤立；D02（從橋西望）、D04 幾乎沒有變化。
4. 構件是 MeshInstance（非 MultiMesh），同 #11；GPU 約 +0.1–0.2 ms。
5. A8 北側雜木林有 3 株羊齒、B8 有 1 株躑躅等 15 件被放置規則擋下（`build_final.txt` 的「落ち」），未補。

## 10. 延後項目與依賴

| 項目 | 依賴／需要的決定 |
|---|---|
| EnrichW9P8 掛載（`village_v2.tscn` 3 行，接在 `EnrichW9P4` 之後） | 共享編輯器目前開著 `village_v2.tscn`，未存檔狀態無法確認 → 需使用者授權與編輯器協調（關閉該分頁或由編輯器擁有者執行 `build_w9p8.gd -- --attach`） |
| ① 除錯層外露 | 改 `main.gd`（共享）或 `gen_village_v2.gd`＋重生主場景；獸道 portal 由另一 session 開發 → 需授權與協調 |
| ② 丘腳社寺 | TASK E 方向（使用者提供參考或選方向案）→ 才能 replace |
| ⑤ 主街南段路口・火見櫓前 | P10／P9 封存範圍是否可開 |
| B7／F7 跌水（#9） | 未授權不改 P8 水體 |
| D1–D5 | P9／P8 封存層；可見度低或本來就是開闊地，暫不建議動 |
| Kit 町家屋頂重複（主街北段 s≈110–178 m、東北聚落 19 棟） | 建築批次（不是環境 overlay 能解決） |
| 既有：#22–#27 相機整合／預算／placement audit | 維持原狀，本輪未處理 |

## 11. 需要使用者裁定

1. A8／B8 的 ART_REVIEW 裁定（是否值得掛載；B8 的效果偏弱）。
2. 是否授權掛載 EnrichW9P8 到 `village_v2.tscn`（與編輯器擁有者協調）。
3. 是否授權處理除錯層（#1）及修改位置。
4. 丘腳社寺的造型方向（TASK E）。

## 12. 檔案

- 內容（本任務新檔）：`godot/tools/p13/w9/w9p8_lib.gd`、`build_w9p8.gd`、`verify_w9p8.gd`、`godot/maps/village_v2/gen/enrich_w9p8.scn`。
- 文件：本報告、`review/`（BEFORE／AFTER、r1、全村 S1–S6、除錯層對照、注記地圖）、`evidence/`（JEV 摘要、vision 紀錄、gate、gate 歷史、bake、覆蓋率、效能、封存 hash、除錯層可見性、ID pass、鏡位、`repro/` scratch 腳本副本）、`W9_FOLLOWUP_REGISTRY.md`（新增 #28–#31）。
- 未改：`village_v2.tscn`、P10／P9／P8 封存內容、已核准與 ART_REVIEW 中的建築（含 017／018、Phase 6 四棟）、共享相機／玩家控制器、獸道。
