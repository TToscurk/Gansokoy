# 獸道 S01 R5：林床立體感（R4 Demo 精修＋南段擴區）— ART_REVIEW

狀態：**ART_REVIEW（未批准）**。沒有 commit、沒有 baseline promotion。谷壁照使用者裁定維持現狀（沒有動岩紋、沒有 cliff shell、沒有改地形）。

## 主審問題
> Does this now look like a believable woodland that the player can explore, rather than a park decorated with forest assets?

我的判斷：**擴區：大致是（林下有蕨冠、隈笹、闊葉草本、幼樹、落葉交錯，有林窗與露土，路清楚）。Demo 區：部分是**——壁腳多了一層林緣（灌叢＋幼樹＋高草叢），但那一區本來就是開闊谷底草地，大面積仍讀得出草皮。

## 交付圖（同相機、同 10:00）
| 檔案 | 內容 | BEFORE |
|---|---|---|
| `1_demo_before_after.jpg` | 原 Demo 精修前後（TPS ×2＋寬景） | 已交付的 R4 Demo |
| `2_expansion_before_after.jpg` | 新擴區前後（TPS、寬景、TPS） | R3 地表（此區沒有 Demo） |
| `3_closeup_roots_floor.jpg` | 根、草、灌木、土的近景 ×3 | 同上各自的前一版 |
| `4_tps_through_forest.jpg` | 一般第三人稱穿林 ×3 | 同上 |
| `5_wide_density_openings.jpg` | 寬景：密度與開口 ×3 | 同上 |
| `6_kit_r5_vegetation.png`／`6_kit_r5_wood.png` | 新資產預覽（Blender Workbench；植物圖左側幼樹被構圖裁到，是預覽排版問題，不是資產） | — |

原圖：`before/h10/`、`after/h10/` 各 20 張。

## 做了什麼
**範圍**：Demo 區（x −14…66, z −48…14）＋擴區（鳥居南側，x −44…30, z −99…−54；選這裡是因為 R3 時它是「草坪上一棵棵樹」最像公園的一段）。S01 其餘不動。

**Blender 資產（`assets/beast_path/s01_kit/src/build_s01_kit.py`，CLI 正式匯出；Blender MCP 用於逐件建模預覽與幾何檢查）**
- 原 27 件 GLB 逐位元未變。
- 新增 15 件有意義的不同生長形：稀疏帶穗茅草、拱垂莎草、林下寬葉低草、直立劍羊齒冠、小羊齒、蕗 ×2、擬寶珠型草本、隈笹（寬葉傘，取代細稈「柵欄」感）、楓型／闊葉幼樹、腐朽中空倒木、殘株（斷口＋根張）、第二種露根、枯枝堆。
- 16 件 LOD1（遠景減面版；草／蕨／蕗／笹，約 1/4–1/2 面數），Godot 端 28–34 m 換手。

**Godot 擺放（新 `tools/beast_path/s01_floor.gd`，由 `s01_dress.gd` 呼叫；`s01_dress.json` 的 `floor`／`auto_wood` 段）**
- 依棲地分（開闊／林緣／林下／壁腳），棲地由**林分密度場**（附近樹幹的高斯和）決定——R3 的 canopy 場只在樹冠正下方，S01 八成面積 < 0.1，用它會讓林下幾乎長不出東西。
- 每種植物以「群落」成片：片內接受率接近 1（叢與叢相接、不同種在片緣交錯），片外是空隙；不是到處 0.3 機率的稀疏撒點。蕨群／草本群／笹群由兩個低頻場互相消長，另有林窗場（林下的開口只剩落葉、苔、低草）。
- 變體由低頻噪聲成片選取（同一片是同一種），加非等比縮放與傾斜。
- 林緣結構：幼樹＋灌叢在壁腳、樹群外緣、林窗邊成叢。
- 自動木：露根只給林下約一半的樹（櫻與幼樹除外）；倒木／殘株／枯枝堆在林下緩坡、離路緣 ≥ 3.5–4 m、彼此 ≥ 8 m。另點名 2 件（E1 大杉露根、E2 枯枝堆）在近景裡。
- 路緣淨空沿路起伏、兩側不對稱（噪聲 0.4–2.3 倍基本淨空）。

## 數量與成本
| | R4 Demo | R5（Demo＋擴區） |
|---|---|---|
| 地被 instance | 11,039 | 13,694 |
| 全部 instance × LOD0 面數 | 2.74 M | 5.41 M（另 LOD1 1.68 M；面積約 1.7 倍） |
| MultiMesh 節點 | 196 | 913（其中 LOD1 373；chunk 20 m） |
| 岩／木個別節點（碰撞） | 39（13） | 66（24） |

簡短效能 sanity（`evidence/perf_sanity.txt`，本機 1600×900）：
- Demo 同機位：R5 實際繪製 primitives 比 R4 **少 13–23 %**、GPU 少 0.5–1.0 ms。
- 擴區：S01Dress 讓 GPU **多 3.4–4.3 ms**，最高 c66_fwd 15.9 ms（≈ 63 fps，GPU 受限）。**陰影 primitives 約 ×2.3 是最大單項成本**（蕨冠、隈笹、灌木、幼樹投影）——這是目前明顯的效能問題，若要壓，第一刀是關掉蕨冠的投影。

## 必要檢查（只做與新工作相關的）
- MultiMesh 非 headless 烘焙；存後 CACHE_MODE_IGNORE 回讀：913 節點、25,709 instance、**零矩陣 0**。
- 主路：地被壓在路面上 **0**；最近路緣距離：短草 0.16 m、林下低草 0.14 m、高草 1.29 m、蕨冠 0.96 m、灌木 2.44 m、幼樹 1.98 m。
- 新岩／木（27 件）AABB／接地：`evidence/s01_dress_report.json`。斷枝 3 件（R4 既有資產 `s01_branch_a`）末端翹起 0.55–0.6 m、細倒木 AD18 側枝下 1.35 m（4 頂點）——與 R4 已知現象相同，未修。殘株與中空倒木本輪抓到並修了兩個資產錯誤（殘株斷口面朝下、倒木壓扁後離地 6 cm）。
- 碰撞：倒木／殘株在玩家可達且離路緣 ≥ 3.5 m 才有凸包；地被無碰撞。
- 場景載入：`generate_beast_path.gd --only=S01` 成功、20 機位實際載入拍攝成功。
- S02–S04：對 R4 開工前備份（514 檔）逐檔比對 503 檔相同，11 檔差異全是 S01 相關（kit 來源、S01 工具、S01 生成檔）；`beast_path.tscn` 正規化後 0 行差異；`s01_entrance.tscn` 只差 S01Dress 的 metadata。
- 還原開關：`s01_dress.json` `enabled=false` → 重新生成 → `s01_entrance.tscn` 正規化後與 **R3 Stage 1 備份 0 行差異**；已改回 `true` 並重新生成，與最終版 0 行差異。

## 還原
- 回 R3 Stage 1：`s01_dress.json` `"enabled": false`，跑 `generate_beast_path.gd -- --only=S01`。
- 回 R4 Demo：從 `%LOCALAPPDATA%/hermes/backups/beast_path_s01_r4demo_20261016/` 逐檔複製（見其 RESTORE.md），刪除 R5 新增的 `tools/beast_path/s01_floor.gd` 與 31 個新 GLB。

## 已知、刻意留著的
- Demo 區開闊谷底仍有大面積草皮感；這區靠近村端，規格要求相對開闊，本輪沒有再加密。
- 擬寶珠型草本仍偏挺（只占小片）；部分前景大蕨／闊葉在近距離看得出是資產。
- 谷壁：照裁定維持（普通山壁）。廣角左下的平行亮線是既有物件，非本輪產生。
- LOD1 換手時遠處草叢輪廓會有小幅跳動，未逐格檢查。
