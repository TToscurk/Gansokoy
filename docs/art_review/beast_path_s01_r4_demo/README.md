# 獸道 S01 R4 Demo：Blender 環境資產示範區（ART_REVIEW，未批准）

2026-10-16。依使用者「S01 轉 Blender 資產製作」指示：A 段地形實驗沒有開始（只有提案圖），地形高度沒動；R3 Stage 1 保留為比較基準（外部備份 `hermes/backups/beast_path_s01_r3_20261016`，445 檔 SHA 清單）。只做一個示範區，做完停下來審圖。

## 審圖圖（同一支腳本、同一組相機、10:00；before＝R3 Stage 1，after＝掛上 Blender 資產）

| # | 檔案 | 內容 |
|---|---|---|
| 1–2 | `1_tps_before_after.jpg` | 主審 TPS `d_tps_f1`：主路上朝東看草地與東壁腳（左 before／右 after） |
| 3 | `2_close_rock_vegetation.jpg` | 近景：東壁腳崖面岩段＋碎石＋草／蕨／野草（`d_close`）、f02 岩組旁的倒木與露根（`g_rock_near`） |
| 4 | `3_wide_density.jpg` | 寬景：整片草地＋東壁（`d_wide`）、沿壁腳往北（`d_wide_s`） |
| — | `4_tps_more.jpg` | R3 既有 TPS 機位 `g_rock_tps`／`w30_back_l`／`t25_fwd` |
| 5 | `5_kit_vegetation.png`、`5_kit_rocks_wood.png` | Blender 資產一覽（Workbench 頂點色，1.7 m 標尺） |

原圖：`before/h10/`、`after/h10/` 各 12 張 1600×900。

## 新做的 Blender 網格（27 件，`godot/assets/beast_path/s01_kit/`）

固定種子的 bpy/bmesh 程序建模 `src/build_s01_kit.py`（Blender 5.2.1），存 `src/s01_kit.blend`＋每件一個 `glb/<name>.glb`（Y 上、原點＝貼地點、單一網格）＋ `src/kit_manifest.json`（三角面數／尺寸）。

| 類 | 資產（三角面） |
|---|---|
| 岩 7 | 崖面岩段 `rock_cliff_a`（7680）、`rock_cliff_b`（6400）、半埋露頭 `rock_outcrop_c`（5120）、岩脊 `rock_rib_d`（5120）、苔石 `mossstone_a`（1280）／`b`（320）、碎石叢 `debris_a`（2240）。兩組直立節理＋斜傾層面切出的多面體，不是吹氣石、不是水平疊板 |
| 草 5 | 高草 `grass_tall_a/b/c`（412／348／338，0.6–1.1 m，含基部倒伏葉、穗）、短草 `grass_short_a/b`（168／150） |
| 林下 7 | 蕨 `fern_a/b`（1044／728）、灌木 `shrub_a/b`（1220／1164）、矮笹 `sasa_a`（582）、野草（艾草型）`forb_a`（452）、蓮座型 `forb_b`（132） |
| 地被 4 | 落葉 `litter_a/b`（1008／624）、苔墊 `moss_a`（170）、細枝 `twigs_a`（252） |
| 木 4 | 苔倒木 `log_a`（812）、斷端倒木 `log_b`（854）、露根＋土 `roots_a`（856）、斷枝 `branch_a`（172） |

Blender MCP 有查過連線，但建模用的是 Blender 命令列跑同一支 builder（可重現、不會動到別人開著的 Blender 場景）。這支 builder 也可以用 MCP 執行：`build_all(export=False)` 只建自己的 `S01_KIT` collection。

## Demo 區與擺放

- 範圍：主路東側谷底（村端 z≈+8 往南到 −48）＋東壁腳與壁面，邊緣用噪聲打散。`tools/beast_path/s01_dress.json`（設定）＋ `s01_dress.gd`（規劃）＋ `bake_s01_dress.gd`（非 headless 烘焙，依 MultiMesh Build Rule）→ `maps/beast_path/gen/s01_dress.scn`，`generate_beast_path.gd` 在 `enabled=true` 時掛進 S01。
- 岩／木 39 件（個別節點）：壁腳點名岩 5＋碎石 3、苔石 5、壁面 4 組自動岩組共 12 件（主岩＋副岩＋坡腳碎石；W1 主岩因為太靠樹幹被略過，只留副岩）、壁腳碎石帶 6、倒木 2、露根 3（貼著既有樹）、斷枝 3。碰撞只給玩家走得到、凸出超過 0.45 m 的 13 件（凸包）。
- 地被 11,039 叢，分成 196 個 MultiMesh（各種 × 16 m 區塊），不碰撞，草／落葉不投影。依 R3 地表通道（粗草／落葉／苔／乾濕）、樹冠、坡度、離路距離、岩旁和群落尺度噪聲決定密度：村端偏開闊，越往南、越靠壁腳，蕨／笹／灌木／落葉越多。
- 沒動：地形高度、380 棵森林規劃（樹冠、保護釘點、5 棵櫻）、R3 地表與谷壁程序岩、S02–S04、共用 shader（地被重用 `village_v2/meadow/meadow_grass.gdshader`，只讀不改；岩／木 shader 是 `s01_kit/mat/` 的 S01 專用複本）。

## 檢查（只做指定的幾項）

| 項 | 結果 | 證據 |
|---|---|---|
| AABB／接地 | 39 件都有世界 AABB、埋深 %、凸出高度、底面空隙；碎石不再整叢埋掉、也不在陡壁上懸空 | `evidence/s01_dress_report.json` |
| 主路淨空 | 0 叢在路面上；地被離路緣最近：短草 0.81 m、高草／野草 1.51 m、蕨 1.73 m、笹 2.35 m、灌木 5.24 m；岩／木最近 8.6 m（斷枝），岩 ≥ 44 m | 同上 |
| MultiMesh 烘焙 | 非 headless；CACHE_MODE_IGNORE 回讀 196 節點、11,039 個 instance、零矩陣 0 | `evidence/logs/bake_final.log` |
| 場景載入 | generator 載入並實例化 `s01_dress.scn`；拍攝程序載入整張地圖、12 機位全部成功 | `evidence/logs/gen_final.log`、`capture_after.log` |
| S02–S04／R3 完整性 | 對 R3 備份 445 檔：442 檔逐位元相同；不同的只有 `generate_beast_path.gd`（加了掛載函式）和兩個 .tscn。兩個 .tscn 去掉 Godot 每次存檔都會換的亂數 id 後，`beast_path.tscn` 完全相同，`s01_entrance.tscn` 只多出 S01Dress 一個節點。S02–S04 相關檔失敗 0 | `evidence/logs/integrity_vs_r3.txt` |
| 關閉開關 | `enabled=false` 重生：maps 312 檔逐位元相同，`s01_entrance.tscn` 正規化後跟 R3 一模一樣（diff 0）→ 一個開關就回到 R3 Stage 1 | 同上 |

沒跑完整驗證、沒跑 GPU 效能測試。地被全部 instance 合計約 274 萬三角面（還沒做距離剔除前）；有距離縮小、可見距離剔除，但沒有中／遠 LOD 網格。擴到整區之前應該先量 FPS。

## 自評與還沒解決的（用圖像模型評的，不算美術批准）

- TPS：before 2–2.5／5 → after 3.5–4／5；近景 6 → 8／10；寬景 5.5 → 7／10。草地不再像修剪過的草坪，壁腳有了「草 → 野草／蕨 → 灌木 → 碎石 → 岩」的層次；主路清楚，村端相對開闊。
- **谷壁：Blender 岩組只能局部打斷，壁面整體還是讀得出平滑坡面。** 壁面中段的岩組（W2–W4）有節理面也有坡腳碎石，但從 TPS 距離看仍然像「岩貼在坡上」。原因在大尺度的形：幾公尺大的岩塊蓋不掉 30–60 m 長的平滑坡。不改地形的下一步可以試：用 Blender 做 10–15 m 寬的崖面「岩殼」整片蓋在壁面上（貼合地形、只露出岩棚與凹槽），而不是加更多單顆岩。要不要做、或改回地形方案，等審圖決定。
- 草地近景：地面材質跟草叢的疏密還沒完全對上（有些地方看起來是「草叢放在地毯上」）；同一種高草的輪廓仍然認得出來。
- 壁面岩組有 2.5–7.5 % 的頂點是下緣懸出（陡壁上的岩棚本來就會懸出，但要你目視確認）；斷枝末端離地 0.55–0.7 m（細枝翹起，沒近看驗證）。
- 落葉／細枝在 Demo 區用得少（35／2 叢），林內的落葉層要等往南擴的時候才看得出效果。

## 開關／還原

- 關掉：`s01_dress.json` 改 `"enabled": false` → `generate_beast_path.gd -- --only=S01`（已實測，跟 R3 一樣）。
- 重做：改 builder → Blender 匯出 → `bake_s01_dress.gd`（**不可加 --headless**）→ 重生 S01。
- 完整還原到 R3 Stage 1：照 `beast_path_s01_r3_20261016/RESTORE.md` 逐檔還原，再刪掉這輪新增的 `assets/beast_path/s01_kit/`、`tools/beast_path/{s01_dress.gd,s01_dress.json,bake_s01_dress.gd,s01_demo_shots.gd}`（含 .uid）、`maps/beast_path/gen/s01_dress.{scn,_report.json}`。

沒有 commit、沒有升級基準、沒有 ART_APPROVED。迭代過程的截圖（a1–a9）放在 scratch，不進 repo。
