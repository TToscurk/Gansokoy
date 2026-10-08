# P10 R5–R6 Environmental Rehabilitation — MASTER AUDIT / ART_REVIEW REQUEST

- 日期：2026-10-09　模式：**AUDIT_ONLY**（AUTO_ADVANCE false）　狀態：**ART_REVIEW REQUEST → STOP**
- 本輪只做稽核＋方案：**未改任何場景、封存、overlay、生成器、NPC、地形**；新增的只有唯讀量測工具與證據檔（見 §7）。
- 量測版本：HEAD `efb7f1b`（branch `yoriichi-combat-and-village-routing`，ahead 106／behind 0）；`village_v2.tscn` sha256 記在 `data/audit_headless.json`。
- 渲染：Forward+（GTX 1070、Vulkan）、1600×900、10:00（DayNight `set_hour`）。審圖站位隱藏 Debug／Portals／QuestAnchors／ParcelLines（無 LANDMARK 大字、無 gizmo）。

---

## 0. 前置確認（HEAD・封存・場景依賴）

| 項目 | 實測 |
|---|---|
| Git | staged 53（使用者先前的 graphify-out 等刪除，**未動**）；unstaged 51（另一 session 的 `main.gd`＋376 行、`trail.tscn`、`slice.meta.json`、`mapRegistry.json` 等，**未動**）。本輪檔案全部 untracked。 |
| 封存實跑 `--seal`（headless，2026-10-09，本輪稽核後） | **12/12 皆 0 項失敗**，各自內建竄改反向都有抓到：HUX（**R4b**）、HUSE（R4）、OUTER（R3e）、CORE（R3d）、POP（R3b）、ACT（R3c）、STR（R2）、MW（R1b）、MKT（R1）、FARM（P8）、P9F（P9 R1–R5 final）、NPCLIB。 |
| R4b 是否真的封存 | `data/village_v2_p10r4b_seal.json` status＝ART_APPROVED；`verify_village_v2_human_use_exp.gd --seal` 0 失敗；反向「把 rejected 的 C 13 件放回 snapshot」→ 與場景、與承認時 A/B 都不一致（偵測成功）。正式＝A 5＋B 5 群 40 件、C 0。 |
| NPC | 51（R3b 16＋R3d 23＋R3e 12，依 R3d／R3e scope-aware 計數），本輪未移動。 |
| 場景掛載順（實讀 village_v2.tscn） | Vegetation：ForestP9→BambooP9→HiedaGardenP9→ShrineGroveP9→SchoolYardP9→WatersideP9→TowerYardP9→SuzunaanP9→GeidonteiP9→KirisameP9→GroundcoverP9→MeadowP9；Props：MarketP10→StreetP10→MarketWestP10→EnvironmentP9；root：HumanUseP10→HumanUseExpansionP10；Population：PopulationP10→ActivityP10→CoreP10→ActivityCoreP10→EntranceCueP10→OuterP10→ActivityOuterP10；P7 Riverbank 65 區塊。 |
| **正式流程是否進得到 V2** | **進不到。** `trail.meta.json` 的村側 portal target＝`slice`；`main.gd` 把 `village`／`人間之里` 一律轉成 `slice`（`load_map` 434–437、`_on_portal_entered` 1186–1187）；`village_v2.meta.json` 註明「正式遊戲的人間之里仍是 slice（計畫 §52）」。V2 只在 debug 的 dev review start（`dev/review_start.json`）或 `--map=village_v2` 才載入。總計畫 §52「最終切換」要求 Portal／Quest／NPC anchor／Save／Performance／Visual 全過才切。→ 本稽核的「獸道→進村」以 layout 的 `PORTAL_TRAIL` 落點 (224, 172)、`arrival_yaw` 0（向北）模擬。 |

---

## 1. 總表（依建議處理順序）

| Issue | 問題（使用者分級／實測嚴重度） | 一句話根因 | 封存依賴 |
|---|---|---|---|
| R5c-01 | 可見世界斷面：東緣約 288 m＋北／南水路出口，地表直接切在天空前（P0；**物理掉落 0**） | P1 地形網格只到 frame 邊（x 0–560、z −340–220），frame 外沒有任何地形／遠景；四面是隱形牆 | P1 凍結（不動）；新 overlay 可行 |
| R5c-02 | V2 跨圖落點 fallback：到 trail／hieda1f／kourindou 一律從 (0, 40, 0) 自由落下 1.85 s、落在 y 3.1–4.2（室內圖疑似落在屋頂）（P0） | `main.gd _place_player` 找不到 `target == "village_v2"` 的 portal → 用預設 `Vector3(0,40,0)` | main.gd（另一 session 未提交修改中）；§52 Portal regression |
| R5c-03 | 隱形牆沒有視覺理由；四邊 10 m 邊界帶 70/70 取樣全部 ≤ 52° 可走到牆 | `gen_village_v2.gd _boundary()` 只放 4 道 1 m 厚、y −10…80 的 Box；邊緣沒有林帶／崖／水作視覺阻隔 | P1 |
| R5c-04 | 正式流程「獸道→人間之里」實際載入舊 `slice`（INFO／決策） | 總計畫 §52：V2 未完成前正式遊戲不得指向 V2 | §52 |
| R5a-01 | 道路像灰模劃線／貼片（P1） | P3 道路＝**等寬直邊 ribbon**（`_ribbon(…, func(_p): return hw, …)`）浮在地形上 0.06–0.10 m；路肩過渡只發生在 ribbon 內，外緣是一條幾何直線＋材質斷層 | P3 道路（base 生成器）、P7 地面 shader |
| R5a-02 | 田地材質混入道路／第二套田格（P1） | P7 `ground.gdshader` 在 farm 權重 > 0.001 處**程序化畫 24×16 m 田格與畦**（93–104 行），與 P8 實際田形不對位；FarmlandTerrain 在 中橫街／南橫街／丘腳街／河岸小徑 路下 80–100 %、路肩 2 m 內 83–100 % 頂點 farm > 0.1 | P7 R1 `_matlib`（雜湊鎖）、P8 封存 |
| R5a-03 | 田埂道中央「綠色裂縫」＋4 條直線田埂道切過田區（P2） | 田埂道 ribbon `center_grass 0.8`（gen 846–847）在中軸畫草帶；layout 田埂道是 x 372／440／500、z 0／70 的直線 | P3、P8 |
| R5a-04 | 局部 ribbon 浮邊／埋入（P2） | 橋頭／岸坡處 ribbon 頂點高出地形：丘腳街 1.46 m @(362,−131)、河岸小徑 0.59 m @(502,−95.5)、龍神道／中橫街 0.35 m；中橫街／FarmPath_1/2 有 −0.02～−0.03 m 埋入（z-fight 風險） | P3、P7 橋頭 |
| R5a-05 | 牆根與地面接觸過乾淨（P2） | 牆根語彙只在 P6 R4 店先帯（街側）與 P9 R5 Macro C（後院 pilot 區）；側牆／背牆大多直接落在平滑地面 | P6 R4、P9 R5（封存） |
| R5b-01 | 水車功能未定義＋機構矛盾、「高架水道」（P1） | P5 水車＝**下掛け（undershot）葉板輪、16 葉板、無柄杓**；P8 卻把三座都當揚水車（受け樋頭架在東軸承柱、槽底 3.30 m）；P9 R4-4／P10 R4 C2 又放石臼・米俵暗示搗き，但沒有水車小屋／杵 | P5 Protected、P8、P9 R4-4、P10 R4 |
| R5b-02 | 水渠／西渠的去向無法解釋（P1） | 穿村水渠 −1.13→−1.63 單調下降後在南緣 (288, 220) 直接出圖、無承接；西渠水源 (70,−178) 無可見湧水、去向同為南緣 | P1／P2 凍結 |
| R5b-03 | 主河缺生活使用痕跡（P2） | 河寬 13–30 m、水面 −0.80／床 −3.2（約 2.4 m 深）可行小舟；P7 已有雁木 3＋石段 21，但無舟、無荷揚げ；主河水面全程 −0.80（零坡度，流向只靠 layout） | P2、P7（封存）；R4b C 水岸已被否決 |
| R6b-01 | 進村主軸的端景是普通町家（P1） | 入口道路軸心→MKT_019（147 m）、鳥居→主街軸心→MKT_023（159 m）、主街各段→MKT_018／MKT_021／MXC_018；**南橫街東望軸心直接打到世界邊界（390 m）** | P3／P4（凍結）、P10 R2（MKT_023 角店有封存的市の入口標識） |
| R6b-02 | 地標可讀性（P1） | 鳥居到站即是視覺主體（OK）；火見櫓被鳥居右柱與屋頂遮去一部分；山頂社殿 ~400 m 只剩一小塊屋頂；參道鳥居沿主街前 299 m 都被 MKT_023／003／031 擋，最後 14 m 才出現 | P4（`main_north`＝intentionally occluded，2026-10-02 裁定） |
| R6b-03 | 參道像泥坡（P1） | **沒有石段**：HillApproach 是 5 m 寬 secondary 道路 ribbon，鋪在 P1 定坡上——s 39–82 m 幾乎全段 30°（`terrain.approach.max_deg 30`），s 35→86 m 爬升約 28 m；路面參數與一般次要街道相同（車轍 0.4、碎石 0.25） | P1／P3、P9 R4-2 ShrineGroveP9（封存） |
| R6b-04 | 參道節奏與框景不足（P2） | 燈籠只有 4（鳥居前 2、拜殿前 2），30° 坡段 0；丘腳社寺仍是 P4 灰盒（DEFERRED，待參考圖） | P9 R4-2、P5 |
| R6b-05 | 參道鳥居腳轉身時相機入地 ~0.9 s（P2，P10 FINAL C1） | SpringArm 在 30° 坡上被地形壓入 | 相機系統（單獨 tech debt） |
| R6a-01 | **建物灰暗的主因**（P1） | `_matlib` 建物材質 `albedo_k 0.42`（P1 時為 **Compatibility** 校正的地表反照率係數）原封用在 Forward+ 正式渲染：**日照下白漆喰 luma 0.431，比 18 % 中性灰卡（0.650）還暗**；去掉係數同卡為 0.912 | P5 Asset Gate（`_matlib` 逐檔雜湊）→ P5–P10 全部審圖基準 |
| R6a-02 | 陰面一律偏藍、低飽和（P2） | 環境光＝SKY（energy 1.0、sky contribution 1.0）：中性灰在陰面 sRGB (0.265, 0.349, 0.475)、飽和度 0.44 | P13 global lighting debt（已登記） |
| R6a-03 | 複製感（P2） | 參數上 187 棟**全部唯一**（full signature 187/187、25 m 內同款 0），但 5 個材質全村共用、屋根網格只有桟瓦 `l_roof`＋2 色調變體（無茅葺／板葺）、pitch 0.45 全村一致、色調只 3 段（t0 62／t1 66／t2 59）、側牆大面空白 → 參數差異被同一調色盤壓平 | P6 R1–R4（R3 ART_APPROVED） |
| R6a-04 | 街區性格弱（P2） | 高視角屋頂佔畫面 30–35 % 且同色；市場／住宅／農家／水岸沒有材料或色彩分區 | P6、`_matlib` |
| R4c-01 | 稲架「稻草穿透」（P2） | `street_kit st_hasa`：稲束是半徑 0.06 m 的錐柱、頂端中心在 z ±0.03，竹竿半徑 0.025 在 z 0 → **竿從稲束中心穿過**；上段穗端 y 1.12 與下段束頭（y 1.12）同高重疊；X 脚斜穿稲束列。用在 9 處 | P10 R2 street_kit（封存）、R4／R4b／StreetP10 擺放 |
| R4c-02 | 用途看不懂（P2） | 千歯扱き被前景桶遮住（2/5）、筵上散件（2/5）、A 字農具掛け（2/5）、唐箕（3/5）、藁塚讀成編籠（3/5）、稲架下背負い籠被稲束遮（2/5） | P10 R4／R4b（封存） |
| R4c-03 | 透明／幾何錯誤（INFO，未重現） | props 群 StandardMaterial 透明面 0；植被 `veg_leaf`＝alpha scissor；`gc_*` 地被為 blend＋depth_draw_never（地面層）。藁物頂點進入他物碰撞 0、地形下 ≤ 0.09 m（刻意埋入；柴垣杭 0.30 m） | — |
| R4c-04 | 米俵／石臼讀成筒（P2，既有） | R4-4 已記錄為資產本體限制、待使用者裁定（§31.21） | P9 R4-4 |

---

## 2. 逐項明細

> 欄位：問題與嚴重程度／Root Cause／路徑／系統與封存依賴／建議解法與備選／可調參數／風險與效能／BEFORE 證據／驗收 Gate。
> 證據圖都在 `docs/art_review/village_v2_p10_rehab_audit/before/`（`*_a`＝NPC ON、`*_b`＝NPC OFF），量測 JSON 在 `data/`。

### R5c — World Boundary Closure（P0）

**實測結論（先講）：V2 內「正常移動掉入虛空」在本次涵蓋範圍內＝0 次，未能重現。** 可以重現的是 (1) 走到邊上看得到世界被切斷（R5c-01/03），(2) 從 V2 經 portal 到其他圖會從 40 m 高空落下（R5c-02）。若使用者實際掉落的地點不在下列範圍，請提供位置，我再針對該處重測。

涵蓋範圍：
- 地形碰撞 1 m 格 312,481 格（front-face only）、2 m 格 78,400 格：無地形 0、只有背面 0。
- 2 m 格 BFS（上坡 ≤ 52°、下坡不限、邊界牆擋、出界方向再以玩家膠囊 r0.3 h1.7 cast）：V2 可達 74,691 格、**VOID_EXIT 0**；同法 trail 12,828／0、slice 29,824／0（`data/mapedge_*.json`）。
- 真玩家（main.tscn＋ReviewStart＋CharacterBody3D）在 15 個邊界／角落點朝外 sprint＋連跳 3.5 s：**15/15 PASS**，全部停在牆內 0.3 m（x 559.7、z −339.7…），最低 y 未低於起點地面（`data/runtime_boundary_portals.json`）。

#### R5c-01 可見世界斷面
- **嚴重度**：P0（視覺）。東緣 6 段約 288 m 與地形同高或更低（z −154…−138、−114…−74、−18…78、102…158 等）、北緣 x 370–394（主河出口）、南緣 x 122（西渠）／282–290（水渠）。從田區 15 m 外就看到「草地直接切在天空前」；高視角整條東緣是一道斜線斷口。南橫街東望的軸心射線 390 m 處直接打到 `Collision/Boundary`（街道端景就是世界盡頭）。
- **Root cause**：P1 地形 4 片網格的 xz 範圍＝frame（MainTerrain 0…560／−340…220），frame 外沒有地形、林、遠景；霧 density 0.000546 不足以遮。邊界只靠 4 道隱形牆。frame 外只有 ForestP9 24、MeadowP9 65 個 chunk 的 AABB 略超出（植被，不是地面）。
- **路徑**：`Terrain/{MainTerrain,FarmlandTerrain,RiverTerrain,NorthHill}`、`Collision/Boundary`；生成器 `tools/gen_village_v2.gd _terrain()`／`_boundary()`（1362–1385）；`layout_v2.json relief.east_*`（東緣抬升只在 z_fade 範圍）。
- **系統／封存**：P1 Terrain 凍結（P1 regression 永久）、P2 水系凍結。frame 內地形不可改。
- **建議**：**A（推薦，非破壞）**＝新 overlay `World/EdgeClosureP10`（root，HumanUseExpansionP10 之後）：
  1. frame 外 200–600 m 的**遠景地形裙**（只畫、無碰撞）：東側＝延伸的田野→河岸林→低丘、北側＝山、南側＝林；主河在東緣與北緣**延續出去**、水渠在南緣接進遠景的川（同時回答 R5b-02）。
  2. frame 內側 0–30 m 的**邊緣林帶／生垣／土手**（東緣田區用「防風林＋土手」，水路出口用「樋門＋河畔林」），讓隱形牆落在一個看得懂的阻擋後面。
  3. 距離霧只作補助（屬 P13，不在本包）。
  **B**：P1 解凍、把東緣做成土手或丘（改地形，需 reopen P1，影響 P1／P2／P7／P8 gate）。**C**：只靠霧（全域，違反「不得全局掩蓋」）。
- **可調參數**：`skirt_radius_m` [200, 600]、`skirt_relief_m` [3, 25]、`edge_belt_width_m` [12, 30]、`belt_density` [0.3, 0.8]、`belt_gap_max_m` [4, 10]、`river_extend_m` [80, 300]、`fog_start_m`（P13）。
- **風險／效能**：遠景裙 1 張低面數網格＋impostor 林（建議 ≤ 60k tris、draw call ≤ 10）；林帶若用既有 R1 樹庫 MultiMesh → 必須非 headless build＋MMBAKE。不得碰 P7 riverbank 區塊與 P8 田。
- **BEFORE**：`p0_e_edge_high_a.png`、`p0_e_edge_farm_tps_a.png`、`p0_e_river_exit_tps_a.png`、`p0_n_river_exit_tps_a.png`、`p0_s_canal_exit_tps_a.png`、`r5b_canal_south_exit_high_a.png`、`r5b_river_high_a.png`。
- **Gate**：①既有 BFS VOID_EXIT 0、真玩家 15 點 PASS（不得退步）；②**外望射線**：邊界帶內每 8 m、眼高 1.7 m、朝外 ±30° 的射線，打到「天空且俯角 < 0°」的比例 0（全部先打到地形裙／林／丘）；③東緣 TPS 15 m／高視角 A/B；④overlay 不改 P1 terrain hash、P7 RBG、P8 FARM、MMBAKE 全綠。

#### R5c-02 V2 跨圖落點 fallback
- **嚴重度**：P0（runtime bug，dev review 路線可觸發）。
- **Root cause**：`scripts/main.gd _place_player()`（1282–1320）預設 `spawn := Vector3(0.0, 40.0, 0.0)`，只認 `portal.target == from_id`；trail／hieda1f／kourindou 的 portal 都指向 `slice`，沒有 `village_v2` → 落點＝目標圖原點上空 40 m。實測：trail 落到 (0.3, 4.04, 0)、hieda1f (0.3, 4.20, 0)（該室內圖 portal 地面 −0.3 → 疑似落在屋頂／天花板上，需目視確認）、kourindou (0.3, 3.13, 0)，皆 1.85–1.87 s 後才著地。另 `_arrival_for_portal` 會把落點往**世界原點**內推 4 m（V2 的原點在西緣）。
- **路徑**：`godot/scripts/main.gd`（工作樹有另一 session 未提交的 +376 行）、`data/{trail,hieda1f,kourindou}.meta.json`。
- **系統／封存**：非美術封存；屬總計畫 §52「Portal regression」。
- **建議**：A（推薦）＝`_place_player` 找不到對應 portal 時，以 alias（`village_v2`↔`slice`↔`village`）再找一次，仍無則用 `meta.spawn`／第一個 portal，**永不用 (0,40,0)**；加 headless 回歸（本輪的 `audit_village_v2_rehab_runtime.gd` portals 段可直接當 gate）。B＝在三張圖 meta 加 `village_v2` 專用 portal（資料改動多、§52 前會留下雙入口）。**因 main.gd 正被另一 session 修改，動手前需你確認由誰改。**
- **可調參數**：無（邏輯修正）；`arrival_y_offset`（既有，0.3–2.0）。
- **風險**：低；正式流程（slice）落點邏輯不變。
- **BEFORE**：`data/runtime_boundary_portals.json`（portals 段）。
- **Gate**：三個目標圖的落點離對應 portal ≤ 6 m、0.5 s 內著地、墜落高差 ≤ 3 m；正式流程 trail↔slice 回歸不變。

#### R5c-03 隱形牆沒有視覺理由
- **嚴重度**：P1。四邊 10 m 邊界帶最大坡度全部 ≤ 52°（各 70/70），玩家一定走得到牆；西緣是 21–49 m 稜線，站上去往外看也是虛空。
- **Root cause／路徑**：同 R5c-01；`Collision/Boundary` 4×BoxShape3D（1 m 厚、y −10…80）。
- **建議**：併入 R5c-01 的邊緣林帶／土手／水路樋門；牆位不動（保留物理保證）。
- **Gate**：沿四邊每 8 m 的玩家視角（面向牆 1.5 m），畫面中央 30 % 範圍內有可見阻擋物（林、土手、柵、崖）≥ 90 % 取樣。

#### R5c-04 正式流程未接 V2（決策項，非缺陷）
- 依總計畫 §52 這是刻意的；列出來是因為 R6b「獸道→進村」在正式遊戲裡其實載入 `slice`。本稽核一律以 V2 的 `PORTAL_TRAIL` 落點模擬。

### 空間規劃審核（施工前要先定的三件事）

**(a) 水系拓撲（Source → Flow → Elevation → Function → Destination）**

| 水體 | Source | 流向／水位（實測水面網格） | 功能（現況） | Destination | 判定 |
|---|---|---|---|---|---|
| 主河 MainRiver | 北緣 (392,−340) 外 | 依 layout N→E；水面全程 **−0.80**（340 m 零坡度）、床 −3.2 | 龍神潭、P7 雁木 3／石段 21、龍神橋 | 東緣 (560,−112) 出圖 | 兩端都在可見斷面（R5c-01）；流向只能靠水面 shader 表現 |
| 穿村水渠 Canal | 主河取水口 (388,−172) | −1.13 → −1.40 → −1.52 → −1.63，單調、上游回升 0（3 段落差） | 水車 ×3 所在、P8 三處取水、R4 C3 洗い場 | **南緣 (288,220) 出圖，無承接** | 去向未解釋（R5b-02） |
| 西側細渠 WestStream | 西丘 (70,−178)，水面 7.87 m | 單調 7.87 → −1.19；跌水 B7 (142.8,42) | 寺子屋側景 | 南緣 (122,220) 出圖 | 無可見水源（湧水／溜池），去向同上 |
| P8 灌溉 | 水車 3→T0、水車 1→N0、水車 2→S1（受け樋頭 3.30 m→落とし樋→石桝→土渠／木槽） | 逐田重力，P8 gate 水位誤差 0.0000 m；場景內有 Chute／Siphon／Weir／Trough／Drop 節點（名稱計數含子節點，僅作存在證據，見 `data/audit_headless_water_arch.json`） | 灌溉 | N2／N3 北側暗渠 → 主河 −0.80 | 下游成立；**上游的「揚水」機構不成立**（R5b-01） |

**(b) 進村視線（`PORTAL_TRAIL`(224,172) → 南大鳥居 → 主街 → 參道，眼高 1.7 m、每 4 m、107 站；以碰撞體為遮擋，樹冠無碰撞故植被遮擋被低估）**

| 地標 | 可見站數 | 首次可見 | 主要遮擋（站數） |
|---|---|---|---|
| 南大鳥居 | 63/107 | 0 m（到站即見） | MKT_007（8）、MKT_005（6）、MXC_008（6） |
| 火見櫓 | 84/107 | 0 m | MXC_008（7）；鳥居右柱與屋頂切掉下半（目視） |
| 山頂社殿 | 53/107 | 0 m | 地形自身（15）、MKT_031（5）；~400 m 只剩一小塊屋頂（目視） |
| 參道鳥居 | 28/107 | 299 m（主街最後 14 m） | **MKT_023（18）**、MKT_003（12）、MKT_031（10）、StreetP10（7）、MKT_001（6） |
| 龍神像 | 20/107 | 325 m | SGT_001、MKT_001／003／011——屬 P4 核准的「漸進式揭露」，非缺陷 |
| 鈴奈庵／霧雨店／鯢吞亭／寺子屋／稗田邸 | 0–12 | — | 街屋本身（側街地標，主軸看不到屬正常） |

各直線段軸心的第一個擊中物（端景）：入口道路→MKT_019（147 m）；鳥居→MKT_023（159 m）；主街①→MKT_018（71 m）；②→MKT_021（64 m）；③→北丘地形（262 m，OK）；④→StreetP10 構件（100 m）；⑤→MXC_018（63 m）；參道①→坡面（41 m）；南橫街東→**世界邊界（390 m）**。

**(c) 建物移位／刪除候選（只比較、不建議本輪動）**

| 候選 | 擋什麼 | 保留＋加端景 | 縮小／退縮 | 移位／改路 | 刪除 |
|---|---|---|---|---|---|
| MXC_018（主街北端端景） | 主街⑤軸心、參道入口 | **推薦**：丘腳街路口（300,−130）放參道入口標（社号標／常夜燈一對／石鳥居）作端景 | 平屋化或退縮 2–3 m（P4 massing 局部修改，需核准） | 不建議（P3 地塊凍結） | 可行但需核准；地塊改火除地／廣場框參道 |
| MKT_023（辻の角店） | 參道鳥居 18 站 | **保留**（帶 P10 R2 封存的市の入口標識） | — | — | 不建議（會破 R2 封存） |
| MKT_019（入口道路軸心） | 入口端景 | 推薦：當作「設計過的端景」（看板・2F 意匠），或把軸心焦點交給火見櫓 | — | — | 不建議 |
| SGT_001／002 | 鳥居兩側框 | 保留（它們是框景） | — | — | — |

### R5a — Ground Integration & Historical Aging（P1）

#### R5a-01 道路＝等寬直邊 ribbon（灰模劃線／貼片）
- **嚴重度**：P1。目視（TPS／高視角）：路是「疊在地形上的另一條淺色帶」，邊緣在透視中是長直線、路與地是材質斷層，沒有車轍深度、路冠、側溝、踏み固め的漸層。
- **Root cause**：`gen_village_v2.gd _roads()` 1614–1631：`_ribbon(rpts, func(_p): return hw, func(p): return _level(r, …) + 0.1, …)` → 固定半寬、+0.10 m 抬升；巷道 `LANE_LIFT` 0.06。實測 ribbon 頂點−地形：道路平均 0.097–0.139 m、巷道 0.060 m。地面 shader mode 1 只在 ribbon 內做「路面層→路肩層」（`edge = smoothstep(shoulder_start, 1, |UV.x| + 噪訊±0.15)`），**ribbon 外緣本身是幾何直線**，外面是地形自己的權重（草／田／建成區），兩邊不共用過渡。
- **路徑**：`Roads/MainStreet/{EntranceRoad,MainStreet}`、`Roads/SecondaryRoads/*`（7）、`Roads/Alleys/*`（含 Lanes 7）、`Roads/FarmPaths/FarmPath_1–5`；`maps/village_v2/gen/road_*.res`、`lane_*.res`；`assets/village_v2/_matlib/ground/ground.gdshader`（mode 1）。
- **系統／封存**：P3 道路（base 生成器，ART_APPROVED）、P7 R1 地面材質（`_matlib` gate 逐檔雜湊）。**任何根治都要動 base 生成器或 `_matlib`。**
- **建議**：**A（推薦，根治）**＝在 base 生成器把道路改成「地形權重的一部分」：路面寫進地形頂點權重（street／trodden／gravel／rut），ribbon 只保留在需要的地方（主街鋪面、橋頭），外緣用不規則寬度＋噪訊侵蝕、雨水沖刷、路肩草侵入；→ 需 base 重生＋依序 re-attach 13 overlay＋全回歸（使用者規則 `full_map_rebuild: false` → **需你明確核准**）。**B（非破壞）**＝新 overlay「路緣過渡帶」（沿用 P9 R5 `gc_macro` 類 blend 地面網格）：沿 ribbon 外緣 0.25–1.2 m 畫不規則踏み固め／碎石／草侵入，蓋住直線；ribbon 本身不動。**C**＝只改 `ground.gdshader` mode 1（`shoulder_start`、噪訊幅度）——改不到幾何直邊，效果有限。
- **可調參數**（Pilot 起點，非定值）：`edge_blend_width_m` [0.25, 1.20]、`edge_irregularity_m` [0.08, 0.45]、`surface_variation` [0.10, 0.30]、`vegetation_edge_intrusion` [0.05, 0.18]、`ribbon_lift_m` 0.10→[0.00, 0.03]、`rut_strength` [0.2, 0.5]、`wear_center`、`edge_gravel`；`wear_distribution`：market HIGH／residential MEDIUM／farmland FUNCTIONAL／waterfront MOISTURE_BASED／shrine CONTROLLED。
- **風險／效能**：B 方案的 blend 層與 GroundcoverP9（封存，也是 blend＋depth_draw_never）疊加有排序風險 → 必須避開 GC 封存區或用同一渲染優先序；A 方案重生 base 有連鎖風險（P1 protection、P3 parcels、P7 RBG、MMBAKE、所有 overlay 掛載順）。效能：B 約 +1 張 blend 網格／區塊。
- **BEFORE**：`r5a_main_street_n_a.png`、`r6b_gate_n_a.png`、`r5a_cross_south_to_farm_a.png`、`r5a_cross_mid_east_end_a.png`、`r5a_farm_road_high_a.png`；量測 `data/audit_headless.json`（roads）。
- **Gate**：①ribbon 外緣在 TPS 5–15 m 不再是單一直線（外緣位置沿路標準差 ∈ edge_irregularity 範圍）；②`material_leakage` 0（田／路歸屬用 R5a-02 的遮罩判定）；③`z_fighting` 0（ribbon 低於地形頂點數 0、與 overlay 共面 0）；④`unintended_overlap` 0（不蓋 P7 構件、P8 田、封存 overlay 的 exclusion）；⑤A/B 同機位、ART ≥ 4/5。

#### R5a-02 田格混入道路（第二套田格）
- **嚴重度**：P1。高視角：草地上有一套淡色長方格（畦帶），**不跟 P8 真正的田形走**——出現在水渠與稗田邸之間、稗田邸四周、遠處田區，並延伸到 中橫街／南橫街／丘腳街／河岸小徑 的路肩與路下。
- **Root cause**：`ground.gdshader` 93–104：mode 0 只要 farm 權重 `b.g > 0.001`，就以 `mod(p − paddy.xy, paddy.zw)` 畫 24×16 m 規則田格（`paddy`＝layout `districts.Farmland.paddy` x0 350／z0 −140／dx 24／dz 16、bund 1.2），畦＝踏み固め土 ×1.6、田面＝泥 0.35＋濕 0.12。這是 **P7 時期替 P8 打的底色**；P8 封存後真正的田（67＋7 田、不規則外緣）蓋在上面，但沒蓋到的地方（田間、路肩、農田邊緣羽化 10 m 帶）仍露出 P7 的程序田格。實測 FarmlandTerrain 頂點 farm > 0.1：中橫街路下 61/61、路肩 42/43；南橫街 67/69、48/48；丘腳街 16/17、15/16；河岸小徑 16/20、24/29；田埂道 113/113、229/229。
- **路徑**：`Terrain/FarmlandTerrain`（13,703 頂點，UV.y＝farm 權重）、`ground.gdshader`、`gen_village_v2.gd _ground_mat()` 824–826（paddy uniform）。
- **系統／封存**：P7 R1 `_matlib`（registry gate、`files_sha256` 鎖 shader）、P8 封存（不能動 P8 田）。
- **建議**：**A（推薦，根治、最小）**＝shader 只在「P8 田的實際範圍」內畫田格（P8 生成器已有田形資料 → 烘一張 farm mask 貼圖或頂點權重；P8 未覆蓋處改回草／土），路下與路肩 farm 權重清 0。需 reopen P7 R1 `_matlib`（改 shader → 新雜湊 → 重驗 P7 gate）。**B**＝新 overlay 把田格露出處蓋成草／土（治標，蓋不乾淨的邊會成新的貼片）。
- **可調參數**：`farm_mask_source`（P8 田形 / 頂點權重）、`farm_feather_m` 10→[2, 6]、`road_farm_clear_m` [1.0, 3.0]、`bund_w`（P8 已有真畦，P7 程序畦可關閉）。
- **風險／效能**：A 會改所有含 farm 權重處的地面外觀 → P8 審圖圖需對照（不改 P8 幾何）；效能中性（少一個分支）。
- **BEFORE**：`r5a_farm_road_high_a.png`（第二套格最清楚）、`r5a_farmpath1_n_a.png`、`r5a_farmpath4_e_a.png`、`r5a_cross_south_to_farm_a.png`。
- **Gate**：田格圖樣只出現在 P8 田範圍內（P8 mask 外 shader 田格權重 0）；道路 footprint＋2 m 內 farm 權重 0；高視角 A/B「看不到第二套格」；P8 FARM seal 0 失敗。

#### R5a-03 田埂道中央草帶讀成裂縫
- **嚴重度**：P2。高視角主田埂道中軸一條細綠縫（目視判為「兩片地面之間的裂縫」）。
- **Root cause**：`ROAD_GROUND.farm.center_grass 0.8`（gen 846–847）＋`rut_offset 0.55`：2.4 m 寬路面中央 0.22–0.42 m 草帶。田埂道是 layout 的 5 條直線（x 372／440／500、z 0／70）。
- **建議**：中央草帶改成斷續、寬窄變化、只在少走處出現；或田埂道改為「兩條輪跡＋草」的地形權重（同 R5a-01 A）。
- **參數**：`center_grass` [0.2, 0.6]、`grass_break_len_m` [1, 6]。
- **BEFORE**：`r5a_farm_road_high_a.png`、`r5a_farmpath1_n_a.png`。
- **Gate**：高視角不再出現連續中央縫；TPS 讀為「農道」。

#### R5a-04 局部浮邊／埋入
- **嚴重度**：P2（技術）。浮 > 0.15 m：丘腳街 4 點（最大 1.46 m @(362,−131)，水渠橋頭）、河岸小徑 39 點（0.59 m @(502,−95.5)）、龍神道 21 點（0.35 m @(379,−200.7)）、中橫街 8 點（0.35 m @(330.7,−29.9)）、南橫街 17 點（0.19 m）；埋入：中橫街 3、FarmPath_1 3、FarmPath_2 9（−0.02～−0.03 m）。
- **Root cause**：ribbon 高度取 `_level()`＋0.1，`ok_fn` 只排除刻水道格，橋頭／岸坡邊緣頂點懸在坡上。多數在橋頭（P7 橋頭鋪石可能已蓋住，需逐點目視）。
- **建議**：併入 R5a-01 的生成器修正（頂點高度改取 `max(地形, 路面設計高)` 並限制懸空）；不另做 overlay。
- **Gate**：ribbon 頂點離地 > 0.05 m 為 0（橋面除外）、低於地形 0。
- **證據**：`data/audit_headless_roads_float.json`。

#### R5a-05 牆根接觸過乾淨
- **嚴重度**：P2。目視：建物底部多是乾淨地面＋深色基礎帶，缺雨落ち溝、泥濺、苔、堆積。
- **Root cause**：牆根語彙只存在於 P6 R4 店先帯（街側 29 種 fr_* 構件）與 P9 R5 Macro C（3 個 pilot 後院）；側牆、背牆、非 pilot 區沒有。
- **建議**：R5a Pilot 內加「牆根帶」（雨落ち 0.6–1.0 m 碎石／濕土、跳ね返り苔）作為同一個路緣 overlay 的一部分；**不碰** GroundcoverP9 封存區。
- **參數**：`drip_band_m` [0.5, 1.2]、`splash_moss` [0, 0.3]、`wall_coverage` [0.4, 0.8]（不成圈）。
- **Gate**：Pilot 區 TPS 5–10 m 牆根可讀；不在 P6 R4 店先帯上重疊。

### R5b — Water Logic & River Life（P1）

#### R5b-01 水車功能未定義＋機構矛盾
- **嚴重度**：P1（因果不成立）。
- **Root cause**：P5 R4 `build_waterwheel.py`＝**下掛け（undershot）葉板輪**（雙輪緣、每側 10 輻、16 葉板，Hero 子節點只有 Wheel／Axle／Bearing／Post／Pier，無柄杓、無水車小屋）。葉板輪靠水流推動，**不能把水舀上 3.3 m**；但 P8 r5／r6 的取水全部以「水車軸承受け樋頭（槽底 3.30 m）」為水源（水車 3→T0、水車 1→N0、水車 2→S1），畫面上樋頭直接從軸承柱開始、看不到水從哪來（目視確認）。同時 P9 R4-4 作業場（石臼＋米俵）與 P10 R4 C2「搗きに来た荷」暗示精米／搗き，卻沒有能傳動的小屋或杵。農田面（0.30 m）比水渠水面（−1.13～−1.63）高 1.4–1.9 m，**灌溉一定要揚水**——所以問題不在 P8 的水利，而在水車資產的機構。
- **路徑**：`Landmarks/LANDMARK_WATERWHEEL_{1,2,3}/Hero`、`assets/village_v2/waterwheel/`、`assets/blender/village_v2/build_waterwheel.py`；P8 `gen/farmland_p8.scn`（Chute 5、Feeder 3、Trough 22）；P9 `WatersideP9`；P10 `HumanUseP10/PilotC`。
- **系統／封存**：P5 Hero（Protected 原檔不得覆寫，重製一律另存新資產）、P8、P9 R4-4、P10 R4（都封存）。
- **建議**（每座水車明訂一個主功能）：
  - **A（推薦）**：三座都改成**揚水水車**——新資產 `waterwheel_lift`（另存，不覆寫 P5）：輪緣加柄杓／箱、輪頂旁加「受け樋」承水口，局部座標沿用現有軸承＝P8 樋頭位置不變（P8 幾何不動）。其中**水車 1**（北、R4 C1 修理場）兼「精米小屋」：軸延伸進一間小水車小屋（杵 2–3 本），讓 R4-4 石臼／米俵的作業場有因果。
  - **B**：水車 2 維持「動力＝精米小屋」，水車 1／3 改揚水；水車 2 的 S1 改由水車 1 的支渠供水（要動 P8 取水 → reopen P8）。
  - **C**：只加「水車小屋」不改輪（揚水因果仍不成立，不推薦）。
- **可調參數**：`bucket_count` [12, 20]、`bucket_volume_l` [2, 6]、`trough_catch_h_m`（固定 3.30，對齊 P8）、`mill_hut_size_m` [3×3, 4×5]、`pestle_count` [1, 3]、`splash_fx`（P13）。
- **風險／效能**：新資產要過 Asset Gate 11 項＋水車專項（輪半徑 ≤ 3.2、輪投影在水面內、yaw 對水流）；面數預算水車 ≤ 15k（現 14 %，有餘裕）；P8 取水淨空與 TPS 相機淨空 gate 要重跑。
- **BEFORE**：`r5b_ww2_chute_a.png`、`r5b_ww1_bank_a.png`、`r5b_ww3_a.png`。
- **Gate**：`undefined_waterwheel_function` 0（3 座各有功能＋看得見的機構）；樋頭有水源（柄杓→受け樋連續）；P8 FARM／P5 hero gate／P9 WATER seal 0 失敗；TPS 5–10 m 讀得出「水被舀上來流進樋」。

#### R5b-02 水渠／西渠去向
- **嚴重度**：P1。水渠在南緣 −1.63 m 直接切斷（高視角目視：盡頭是空白背景，無承接、無樋門、無暗渠口）；西渠水源在西丘 7.87 m 處憑空開始。
- **Root cause**：layout `water.Canal.pts` 終點 (288,220)、`Streams[0]` 起點 (70,−178)／終點 (122,220) 都在 frame 邊上，src 註記「南段隱入前景林」——但 frame 外沒有任何東西。
- **建議**：與 R5c-01 同一 overlay：水渠出口做「樋門＋排水路接遠景的川」（遠景裙裡畫出下游），西渠水源做小湧水／溜池＋石組。P1／P2 frame 內水體不動。
- **參數**：`outlet_type`（樋門／暗渠口／落ち口）、`spring_pool_r_m` [2, 5]、`skirt_river_w_m` [8, 20]。
- **Gate**：`unexplained_channel_connections` 0（每條人工水路都有可見的進／出口）；`contradictory_flow_direction` 0（既有單調檢查：水渠上游回升 0、西渠 0）。

#### R5b-03 主河生活痕跡
- **嚴重度**：P2。高視角：河寬足夠行小舟、水面平靜，但看不到舟、荷揚げ、繫船（P7 的雁木與繫船樁在此視角讀不到）。
- **Root cause**：P7 只做護岸與 3 處雁木／石段 21，沒有舟與荷；R4b C 水岸（3 輪）已被否決並「保留自然留白」。
- **建議**：**SPARSE**——只在既有 3 座雁木中選 1–2 處：小舟 1–2 艘（繫在既有樁上）＋荷揚げ（俵 2–3、竿）；不新增岸邊雜物、不重做 R4b C。主河零坡度水面可用 shader 流向（P13）表現下游方向。
- **參數**：`boats` [0, 3]（`DEPEND_ON_RIVER_SURVEY`：可航段 = 河寬 ≥ 13 m、水深 ≥ 1.5 m）、`mooring_points` CONTEXTUAL（只用 P7 既有樁）、`landing_goods` [0, 4]。
- **風險**：R4b C 已三輪失敗——本項只在你要的時候做，且以「一艘舟能否在 10–15 m 讀成『有人在用河』」為唯一標準。
- **BEFORE**：`r5b_river_high_a.png`、`r5b_river_dragon_pool_a.png`。
- **Gate**：`existing_R4_pilot: PRESERVE`（R4 C 三群不動）；新增件 ≤ 8；ART ≥ 4/5。

### R6b — Shrine, Arrival & View Corridor（P1）

#### R6b-01 主軸端景是普通町家
- **嚴重度**：P1。到站時鳥居居中、是第一焦點（OK，目視確認）；穿過鳥居後主街盡頭是普通町家，沒有視覺終點；南橫街東望軸心直達世界邊界。
- **Root cause**：layout 主街是 5 段折線（(234,104)→(236,80)→(242,40)→(262,−20)→(280,−80)→(300,−130)），每個折點後的軸心落在街屋立面；端景只在 P4 時以「龍神像漸進式揭露」設計過，北端 `main_north` 在 2026-10-02 裁定為 intentionally occluded（P10／P13 只做端景強化）。
- **路徑**：`layout_v2.json roads[1]`、`Districts/*/Buildings/B_P_{MKT_019,MKT_023,MKT_018,MKT_021,MXC_018}`、`Props/StreetP10`。
- **系統／封存**：P3／P4（凍結）、P10 R2（MKT_023 角店的市の入口標識封存）。
- **建議**：**A（推薦、不刪不移）**＝在 3 個軸心終點放「設計過的端景」：①入口道路→MKT_019：看板建築化（2F 意匠＋大看板）或在軸上加常夜燈；②主街⑤→丘腳街路口 (300,−130)：參道入口標（石鳥居／社号標＋常夜燈一對），讓主街「終點＝往神社」；③南橫街東端：與 R5c-01 的東緣林帶／土手一起，讓軸心停在林帶而不是虛空。**B**＝MXC_018 退縮／平屋化（P4 局部 massing，需核准）。**C**＝刪 MXC_018 改廣場（需核准）。
- **參數**：`anchor_h_m` [3, 8]、`anchor_offset_from_axis_m` [0, 2]、`lantern_pair_spacing_m` [3, 5]。
- **BEFORE**：`r6b_arrival_n_a.png`、`r6b_entry_mid_n_a.png`、`r6b_gate_n_a.png`、`r6b_main_bend_ne_a.png`、`r6b_main_north_end_a.png`、`r6b_entry_high_a.png`；`data/audit_headless_shrine_vista.json`（vista）。
- **Gate**：`road_termination: VISUAL_ANCHOR_REQUIRED`——每條主軸的軸心射線第一擊中物＝指定端景（landmark 或 anchor）；`building_removal: APPROVAL_REQUIRED`；TPS 進村 3 機位 ART ≥ 4/5（「知道往哪走」）。

#### R6b-02 地標可讀性
- 見 §空間規劃 (b)。**不要求全程可見**；問題是「看得到時讀不出來」：山頂社殿在 337–400 m 外只剩一小塊屋頂（估算畫面高約 15–18 px：主體約 8 m、垂直 FOV 70°、900 px），火見櫓被鳥居柱與屋頂遮去一部分。
- **建議**：不改量體；以端景（R6b-01）＋參道入口標＋參道沿線燈籠（R6b-04）建立「逐步揭露」節奏；火見櫓的可讀性另看 R6a-01 校正後再判（現在整體偏暗）。
- **Gate**：進村 3 機位中，至少 2 個地標（鳥居、火見櫓或參道入口標）在畫面中可辨識（vision ≥ 4/5）。

#### R6b-03 參道沒有石段
- **嚴重度**：P1。TPS 目視：連續土坡、無踏面無蹴上、無石材邊、無燈籠序列，讀起來是普通土路。
- **Root cause**：參道（`Roads/SecondaryRoads/HillApproach`）＝5 m 寬 **secondary 道路 ribbon**，材質參數與所有次要街道相同（mode 1、`rut_offset 0.85`、`rut_strength 0.4`、`edge_gravel 0.25`）；剖面實測：s 0–35 m 平、s 39–82 m **幾乎全段 30°**（63 m 處一小段 20.7°；`terrain.approach.max_deg 30`），s 35→86 m 爬升約 28 m（全程 1.70 → 34.17 m、全長 102.3 m，> 15° 的長度 60 m）。規劃 §P1 原註「石段在 P4／P5」，但之後沒有任何階段做。
- **路徑**：`Roads/SecondaryRoads/HillApproach`、`maps/village_v2/gen/road_hillapproach.res`、`Landmarks/LANDMARK_HILL_TORII`、`Vegetation/ShrineGroveP9`（封存：參道兩側鎮守林、燈籠 4）。
- **系統／封存**：P1（坡度凍結）、P3（道路）、P9 R4-2（封存）。
- **建議**：**A（推薦）**＝新資產 `sando_steps`（石段 kit：踏石、蹴上、袖石、踊り場）沿既有坡面擺放：rise 0.15–0.18 m、tread 0.32–0.40 m、寬 3.0–3.6 m（5 m 路寬內，兩側留袖石＋苔），每 18–24 段一個踊り場（約 7 處）、踊り場放常夜燈一對；**碰撞維持地形斜坡**（30° < 52°，走路不跳動），石段只畫（腳底與踏面誤差 ≤ ±0.09 m）；參道 ribbon 以石段蓋住（或在 base 生成器停用參道 ribbon，需核准）。地表語言：踏石＝石、兩側＝玉砂利／苔，**不用街道的車轍**。**B**＝石段帶碰撞（真階梯；玩家 step_height 0.6 可上，但相機上下顫動、要重測 SpringArm）。**C**＝改地形做折返參道（P1 reopen，不推薦）。
- **可調參數**：`riser_m` [0.15, 0.18]、`tread_m` [0.32, 0.40]、`width_m` [3.0, 3.6]、`landing_every` [18, 24]、`landing_len_m` [1.8, 3.0]、`stone_tone`、`moss_amount` [0.05, 0.25]、`collision_mode`（ramp／steps）。
- **風險／效能**：與 ShrineGroveP9 封存的樹位／燈籠／`sg_ground` 必須避讓（讀封存 overlay 的實際節點，不重算規劃器）；約 180 段×LOD，建議 MultiMesh 或合併網格 ≤ 40k tris；R6b-05 相機問題可能因袖石而加重或減輕——要重跑相機 sweep。
- **BEFORE**：`r6b_sando_foot_a.png`、`r6b_sando_mid_a.png`、`r6b_sando_side_high_a.png`；剖面 `data/audit_headless_shrine_vista.json`（shrine）。
- **Gate**：`distinct_stone_steps` 有（蹴上 0.15–0.18 量測）、`approach_axis` 定義（鳥居→踊り場→社殿中心軸偏差 ≤ 1 m）、`torii_framing`（鳥居下 TPS 看得到第一段石段與上方社殿屋頂）、真玩家上下全程 0 STUCK、頭部穿入 0、SpringArm sweep 入地 0（或不劣於 BEFORE）；ShrineGroveP9 seal 0 失敗。

#### R6b-04 參道節奏與框景
- 燈籠 4（`village_v2_shrine_grove_lib.gd` 419–425：鳥居前一對、拜殿前一對），30° 坡段 0；丘腳社寺仍是 P4 灰盒（`Landmarks/LANDMARK_HILLFOOT_TEMPLE/Block`，DEFERRED 待參考圖）。
- **建議**：踊り場常夜燈（併 R6b-03）；丘腳社寺維持 DEFERRED（等你給參考圖）。
- **Gate**：參道每 15–25 m 有一個節奏點（燈籠／踊り場／鳥居）。

#### R6b-05 參道鳥居腳相機入地（既有，P10 FINAL C1）
- 單獨 camera tech debt；R6b-03 施工後重跑 SpringArm sweep，不在本包內修相機系統。

### R6a — Architectural Identity & Color（P2，但根因 R6a-01 建議提前「裁定」）

#### R6a-01 建物灰暗的主因：albedo_k 0.42
- **嚴重度**：P1（影響全村每一張審圖）。
- **Root cause（量測）**：`_matlib` 的 `V2_Plaster／V2_Wood／V2_Kawara／V2_Stone／V2_Metal` 與 `machiya_kit/V2_MachiyaKit` 全部 `albedo_color = Color(0.42, 0.42, 0.42)`＋`vertex_color_use_as_albedo`（`matlib.json albedo_k 0.42`）。這個 0.42 是 P1 為**地表**定的係數（`gen_village_v2.gd` 58–63：「K=0.42 讓主要地表落在 **Compatibility** ~110–200」；同註記實測同一反照率 Forward+ 比 Compatibility 暗約 35 %：0.25→164／107）。2026-10-02 正式 renderer 改 Forward+ 後沒有重新校正。`V2_WoodRed` 已因「飽和朱色照 0.42 會壓成暗褐」改用 0.80——同一問題的既有證據。
  - **色卡實測**（`probe_village_v2_rehab_albedo.gd`，10:00、Forward+、同一地點，畫面 sRGB luma）：

    | 卡 | 受光面（現況 k 0.42） | 受光面（k 1.0） | 陰面（現況） |
    |---|---|---|---|
    | V2_Plaster（白漆喰） | **0.431** | 0.912 | 0.209 |
    | V2_Wood | 0.234 | 0.566 | 0.127 |
    | V2_Kawara | 0.228 | 0.543 | 0.139 |
    | V2_Stone | 0.296 | 0.741 | 0.157 |
    | V2_MachiyaKit atlas | 0.230 | 0.494 | 0.126 |
    | 參考：線性 18 % 灰 | 0.650 | — | 0.340（偏藍） |
    | 參考：線性 50 % 灰 | 0.905 | — | 0.599 |

    → 白漆喰的實際反照率約線性 0.09（比 18 % 灰卡還暗），木與瓦約 0.02。主街 TPS（`r6a_main_facades_a.png`）畫面 52 % 像素 luma < 0.2，目視「白漆喰讀成灰／灰褐、木頭接近黑」。
- **路徑**：`assets/village_v2/_matlib/{V2_Plaster,V2_Wood,V2_Kawara,V2_Stone,V2_Metal}.tres`、`matlib.json`、`assets/village_v2/machiya_kit/V2_MachiyaKit.tres`；地面 `ground_k 0.19`（與 0.42 對齊）。
- **系統／封存**：P5 Asset Gate（registry `_matlib` 逐檔雜湊）→ 所有 Hero／kit／props 共用 → P5–P10 的核准審圖圖都以現亮度為基準。
- **建議**：
  - **A（推薦）**＝「逐材質物理校正」（不是全村等比提亮）：在 Forward+ 下以色卡對真實反照率重定每個材質（白漆喰 > 木 > 瓦，各自不同倍率；瓦本來就暗，幾乎不動），先在**獨立審圖場景**做 A/B 與 3 條代表街景比較，你核准後才寫回 `_matlib` 並依序重驗受影響封存。
  - **B**＝只做街區局部 accent 材質（新材質，不碰 `_matlib`）——根因留在全村其他地方，灰暗不會消失。
  - **C**＝曝光／環境光（全域、等幅提亮，違反本次規則，不推薦）。
  - **時程調整理由**：R5a／R6b／R4c 每一個 Pilot 的 ART_REVIEW 都在判斷亮度與材質；若校正在最後才做，前面的審圖要重看。所以建議**把 R6a-01 的「方針裁定」提前到空間規劃審核同一批**（只裁定、不施工）。
- **可調參數**：每材質 `albedo_k`（現 0.42）：Plaster [0.65, 0.90]、Wood [0.50, 0.70]、Kawara [0.42, 0.55]、Stone [0.55, 0.75]、MachiyaKit [0.50, 0.70]；`vertex_tone`（t0–t2）幅度；`global_saturation_boost` 固定 DISABLED（`adjustment_saturation` 保持 1.05）。
- **風險／效能**：效能 0；美術風險大（全村外觀一起變）→ 必須 A/B＋你核准；受影響封存需「重驗＋reseal history」，不是靜默改。
- **BEFORE**：`albedo_cards_sun.png`、`albedo_cards_shade.png`、`albedo_cards.json`、`r6a_main_facades_a.png`、`r6b_gate_n_a.png`、`r6a_roofscape_high_a.png`。
- **Gate**：受光面白漆喰 luma ∈ [0.70, 0.85]（且 < 50 % 灰卡）、木 ∈ [0.35, 0.50]、瓦 ∈ [0.25, 0.40]；主街 TPS luma < 0.2 像素比例 ≤ 30 %（現 52 %）；全域 exposure／saturation 不變。

#### R6a-02 陰面藍色天光
- 中性灰卡在陰面 sRGB (0.265, 0.349, 0.475)、飽和度 0.44（藍）；暖色材質進陰影就變藍灰。環境：ACES（tonemap_mode 3）、exposure 0.98、white 1.0、ambient＝SKY energy 1.0／contribution 1.0、SSAO on、SDFGI off、volumetric fog on。
- 已登記為 **P13 global lighting／sky ambient debt**（P9 R4-3 裁定）。建議：維持 P13，但 R6a-01 的 A/B 要同時給「陰面中性灰的色偏」數據，避免把藍色誤當材質問題。

#### R6a-03 複製感
- **實測**：P6 kit 187 棟（RSW 81、MKT 60、MXC 24、RNE 19、SGT 3）：style 134 種、style＋roof＋bays 184 種、full signature 187/187 全唯一、25 m 內同款 0；主題 9 種（amado 28、mado 27、koshib 25、koshir 23、koshi 21、open 18、bengara 15、lattice 15、mixed 15）、屋根 8 類、bays 3–6。→ **不是參數重複**；複製感來自：材質 5 種全村共用（V2_Wood 7578 面、V2_KitStoneTri 6436、V2_Kawara 3973、V2_Plaster 3821、V2_MachiyaKit 3531）、屋根網格只有桟瓦 `l_roof`＋2 色調變體（無茅葺／板葺）、pitch 0.45（24°）全村一致、色調 3 段、側牆大面空白；加上 R6a-01 把差異壓暗。
- **建議**：先做 R6a-01；之後在 P6 kit 生成器加「街區調色盤」：市場＝弁柄／黃土壁＋暖色暖簾、住宅＝土壁（淡黃土）＋板張り、外圍農家＝**茅葺／板葺屋根**（目前 0 棟）、水岸＝風化板壁、神社周邊＝素木＋白壁（克制）；側牆加下見板／腰板／窓／掛け物。要動 base 生成器（P6）→ base 重生（需核准）。
- **參數**：`district_palette`、`roof_material_mix`（kawara／kayabuki／itabuki 比例）、`side_wall_detail` [0, 1]、`aging`（市場 high／住宅 medium／神社 low）。
- **Gate**：`identical_facade_repetition` REDUCE（同街 30 m 內「材質＋屋根材＋主題」三者全同的鄰棟 ≤ 10 %）；高視角屋頂色相／明度分布至少 3 群；全域飽和度不變。

#### R6a-04 街區性格
- 高視角目視：屋頂佔畫面 30–35 %、同一暗灰，市場／住宅只能靠屋台顏色分辨。**建議**＝R6a-03 的調色盤；`accent_colors: LOCALIZED`（暖簾、看板、幟只集中在市場與主街）。
- **BEFORE**：`r6a_roofscape_high_a.png`、`r6a_ne_residential_a.png`、`r6a_main_facades_a.png`。

### R4c — Prop Readability & Geometry Repair（P2）

#### R4c-01 稲架「稻草穿透」
- **Root cause（資產幾何，`assets/blender/village_v2/build_street_kit.py` 606–621）**：
  - 竹竿：`pole(m, (−1.55, y, 0), (1.55, y, 0), r 0.025)`，y＝1.10／1.60。
  - 稲束：每個位置兩支 `rcy(top=(x, y+0.02, ±0.03), bot=(x±0.03, y−0.48, ±0.14), r 0.06→0.085)`——頂端圓心離竿軸 0.036 m，小於 0.06＋0.025 → **竿穿過稲束內部約 5 cm**，兩半稲束頂端也互相重疊。
  - 上段穗端到 y 1.12，正是下段束頭（y 1.12）→ 兩段在 z 0.055–0.09 重疊。
  - X 脚 `beam((x−0.35,0,0.3)→(x+0.1,1.9,−0.05))` 斜穿中央稲束列。
  - 使用處 9：`HumanUseP10/PilotA/A1_hasa`（2）、`HumanUseExpansionP10/ZoneA/XA3_hasa`（3）、`Props/StreetP10/FarmEdge`（4）。
  - 外加讀感：稲束是均一錐柱、平面感強（目視「像板或百葉」3/5）。
- **系統／封存**：P10 R2 street_kit（封存，資產 rework＝新資產或 kit 版本＋reseal）、R4／R4b／R2 擺放（封存）。
- **建議**：新資產 `st_hasa_v2`：稲束改「跨竿對折」——兩半束在竿兩側外掛（竿與束淨距 ≥ 0.01 m，綁縄在竿上方）、穗端不碰下段、X 脚移到束列之間的空檔；束形不規則（長短、張開角、散草）；替換 9 處（只換 mesh，位置不動）。
- **參數**：`sheaf_count_upper/lower`、`sheaf_spread_deg` [10, 35]、`sheaf_len_m` [0.40, 0.55]、`row_gap_m` ≥ 0.05、`stalk_noise` [0, 0.3]。
- **Gate**：`geometry_penetration` 0（竿×束、束×束、脚×束的網格距離檢查）；TPS 5–10 m 讀成「稲架」4/5。
- **BEFORE**：`r4c_hasa_A1_a.png`、`r4c_hasa_XA3_a.png`、`r4c_farmedge_hasa_zuka_a.png`。

#### R4c-02 用途看不懂
- **實測（目視評分，identity／purpose）**：A2 脫穀作業床——千歯扱き 2/1（被前景桶遮住）、桶 3/2、筵 4/3（平板感）、筵上散件 2/2、唐箕 3/2、俵 4/3、大八車 4/4、藁塚 3/3（讀成編籠）；橋邊 A 字物（農具掛け）2/1；A1 稲架下背負い籠 2/5（被稲束遮）。
- **Root cause**：①擺放：關鍵輪廓（千歯的齒、籠口）朝向或被同群物件遮擋；②幾何：藁物體積感不足（藁塚光滑、稲束均一）；③脈絡：工具與工作物（稲束→千歯→籾→唐箕）沒有連成可讀的流程。
- **建議**（依 `resolution_priority`：diagnose → placement → material → geometry → remove）：先在封存 overlay 內**只調位置／朝向**（R4 reopen，件數不變）；千歯前放一把稲束、唐箕出口放籾殻堆；藁塚改資產（不規則、縄帯）；仍讀不出的件**移除**而不是加旁邊雜物。
- **Gate**：主要道具 5–10 m `primary_target_score` ≥ 4、次要 ≥ 3；R4／R4b 件數只減不增。
- **BEFORE**：`r4c_dakkoku_A2_a.png`、`r4c_hasa_A1_a.png`。

#### R4c-03 透明／背面（INFO）
- 量測：StreetP10／MarketP10／MarketWestP10／HumanUse 的 StandardMaterial 透明面 0；植被 `veg_leaf.gdshader`＝ALPHA＋ALPHA_SCISSOR（不排序）；`gc_ground／gc_macro`＝blend＋depth_draw_never（地面層，與水面同為透明層，交界需留意）。藁物 42 件頂點：進入「其他」碰撞體 0、地形下 ≤ 0.09 m（設計埋入）、柴垣杭 0.30 m（設計）。**本輪未重現透明錯誤**；若你看到特定物件透明，請給位置。

#### R4c-04 米俵／石臼（既有）
- §31.21 已記錄為資產本體限制（米俵像筒、石臼上臼立在下臼旁），待你裁定；可併入 R5b-01 的精米小屋一起處理。

---

## 3. 建議施工依賴順序（含調整理由）

1. **P0**：R5c-02（main.gd 落點 fallback，需先與另一 session 協調）→ R5c-01／03／R5b-02（同一個 `EdgeClosureP10` overlay Pilot：東緣一段＋水渠出口）。
2. **空間規劃審核（一次裁定）**：水車功能表（R5b-01）、端景位置與建物處置（R6b-01，預設不刪不移）、參道石段方式（R6b-03 A／B）、**以及 R6a-01 亮度校正方針**（提前裁定的理由見 R6a-01）。
3. **R5a**：先決定「base 生成器重生」是否核准（R5a-01 A／R5a-03／R5a-04 的根治都在 base；R5a-02 的根治在 `_matlib`）。不核准就走 overlay（B）。
4. **R5b**：`waterwheel_lift` 新資產（P5 Protected 另存）→ 小水車小屋 → 河的 SPARSE 生活點。
5. **R6b**：參道石段 Pilot（鳥居→第一踊り場）→ 端景 anchor。
6. **R6a**：校正（若 2. 選 A）→ 街區調色盤 Pilot（市場一街區＋住宅一街區）。
7. **R4c**：`st_hasa_v2`＋A2 擺放調整。
8. **FINAL WALKTHROUGH**（沿用 `walk_p10_final.gd`）。

每一步只做代表性 Pilot，ART_APPROVED 前不全圖套用。

## 4. 需要你裁定的事項

| # | 決策 | 選項（推薦在前） |
|---|---|---|
| D1 | R5c-02 修 `main.gd` 落點 fallback | 由本線修（需先處理另一 session 的未提交 main.gd）／交給那個 session／暫緩 |
| D2 | 邊界封閉方式 | frame 外遠景裙＋邊緣林帶 overlay（P1 不動）／P1 reopen 改地形 |
| D3 | 道路與地面根治是否允許 base 重生（`full_map_rebuild: false` 的例外） | 允許（Pilot 區先、全回歸＋重驗封存）／不允許（只做 overlay） |
| D4 | P7 `_matlib` 地面 shader 是否 reopen（田格只畫在 P8 田內） | reopen／overlay 蓋 |
| D5 | 三座水車的功能 | A：三座揚水＋水車 1 兼精米小屋／B：水車 2 精米、1・3 揚水（動 P8）／C：只加小屋 |
| D6 | 端景與建物 | 不刪不移、加 anchor／MXC_018 退縮／MXC_018 刪除改廣場 |
| D7 | 參道石段碰撞 | 斜坡碰撞＋石段只畫／真階梯碰撞 |
| D8 | 亮度校正時程 | 現在（R6a-01 A/B → 核准 → 重驗封存）／留到 P13 |
| D9 | R4c 封存 reopen | st_hasa_v2 新資產＋R4 A2 只調位置／暫緩 |
| D10 | 主河生活 | SPARSE 1–2 舟＋1 荷揚げ／不做（維持 R4b C 否決後的留白） |

## 5. 驗收規則（沿用本次指令）

- 核心問題 ≥ 4/5 才 ART_APPROVED；次要 ≥ 3/5；Technical PASS ≠ ART_APPROVED。
- 每個 Pilot：BEFORE／AFTER 同機位（本資料夾的 views 檔可直接重拍）、TPS 5–10 m／10–15 m、高視角、正常遊戲鏡頭、必要時 NPC ON／OFF、乾淨畫面；技術 gate、反向案例、回歸、相關封存雜湊。
- 新 overlay 一律掛 root（HumanUseExpansionP10 之後）——R3b scene gate 對 `Props` 子節點做完全一致檢查，掛 Props 會破 R3b。新擺放物要避開 MeadowP9 同 seed 規劃株（否則立ち草會從新物件穿出），MultiMesh 一律非 headless build＋MMBAKE。

## 6. 本次限制與未驗證部分

- 審圖撮影工具重現的是 TPS 幾何（樞軸＋臂長），**沒有 SpringArm 碰撞**：`r6a_west_alley`、`r4c_wara_B2`（目視確認相機在屋簷／下屋底下）與可能的 `r4c_mushiro_market` 機位無效，它們的亮度統計不採用、也不當讀感證據；施工 Pilot 時改用真玩家相機重拍。
- 視線分析用碰撞體當遮擋，樹冠沒有碰撞 → 植被遮擋被低估；地標「可見」以目視圖為準。
- 「掉入虛空」只在 V2／trail／slice 的可達範圍與 3 個跨圖落點內測過；hieda1f 落點 y 4.20 是否在屋頂上未目視。
- 未跑 116 項全回歸（本輪無任何內容變更）；只跑了 12 個封存 `--seal`（全綠）。

## 7. 重現方式（全部唯讀）

```text
# headless 量測（boundary／roads／sight／arch／props／env／shrine／vista／water／props_pen／roads_float）
Godot --headless --path godot --script res://tools/audit_village_v2_rehab.gd -- --out=<json> [--section=...]
# 真玩家：邊界 15 點＋3 個跨圖落點
Godot --headless --path godot --script res://tools/audit_village_v2_rehab_runtime.gd -- --review=kirisame --out=<json>
# 任一地圖的可達→無地面出口 BFS
Godot --headless --path godot --script res://tools/audit_village_v2_rehab_mapedge.gd -- --scene=res://maps/village_v2/village_v2.tscn --start=224,160 --out=<json>
# BEFORE 撮影（38 機位 × NPC ON／OFF，附亮度統計 _stats.json）
Godot --path godot --script res://tools/shot_village_v2_rehab_audit.gd -- res://tools/shot_village_v2_rehab_audit_views.json <outdir/> toggle=Population
# 色卡（R6a-01）
Godot --path godot --script res://tools/probe_village_v2_rehab_albedo.gd -- <outdir/>
```

證據：`before/`（76 張 BEFORE＋色卡 2＋`_stats.json`＋`albedo_cards.json`）、`data/`（audit_headless*.json、runtime_boundary_portals.json、mapedge_{village_v2,trail,slice}.json）。

**STOP**——等待你對 D1–D10 的裁定；未經授權不開始任何修改、刪建築、重生地形、解封、重配 NPC 或後續施工。
