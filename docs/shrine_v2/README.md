# 博麗神社 v2（候選）— 交付說明

> 狀態：**ART_REVIEW**（agent 只能給到這一級；`ART_APPROVED` 只有使用者能給）。
> 候選場景 id＝`shrine_v2`，**尚未取代正式 `shrine`**。舊圖 `godot/maps/shrine/` 原封未動，另有備份 `D:/神社/_backup_shrine_r3_20261021`（31 檔，來源／備份／manifest 比對 `bad 0`）。
> 驗證日期：2026-10-22。測試機：GTX 1070、Godot 4.7.2、1280×720、關垂直同步；量測時機器上還開著另一個 Godot 視窗（別的 session），GPU 數字偏保守。

## 1. 怎麼看、怎麼玩

```
godot --path godot -- --map=shrine_v2          # 直接開候選圖（出生在南側入口 −3.8, −1.7, 72.0）
```

- 程式內切換：`main.load_map("shrine_v2", "")`。**注意**：先開別的圖（預設開村）再 `load_map`，原圖的非同步出生會在切圖後下一幀把玩家傳回原圖座標、掉出世界（錄影時踩到）；用 `--map=` 直開最穩。
- 座標：x 東、z 南、y 上；南面 +z 入、往 −z 上山，主軸 x＝0。

## 2. 空間配置（公尺）

| 項目 | 位置 / 尺寸（實測） |
|---|---|
| 可玩範圍 | x −57..57、z −66..80（114 × 146 m）；近景地形 160 × 192 m（x −80..80、z −92..100，201×241 點、0.8 m 格）；中景 ±260 m／4 m 格；遠景 ±1100 m／20 m 格 |
| 參道石階 | 52 階 × 0.16 m ＝ 8.32 m；z 33.0 → 4.4，5 段（11／10／11／10／10 階）＋4 個 2.2 m 中間平台，踏面深 0.38 m、寬 3.2 m，兩側各一列袖石；階下土床 −0.09 m，側坡最低處比踏面低 0.25 m（無大於 0.55 m 的露出牆面） |
| 庭院 | 高 y＝8.32，19 點不規則平台（Chaikin 平滑，外框 x −22..24.5、z −47.5..4.4 ≈ 46 × 52 m）；夯土為主，中央兩列錯位石板（約 0.9 × 1.0 m，縫 4–16 cm） |
| 鳥居 | (0, 1)；寬 7.39 × 高 5.53 m；柱腳外緣 ±2.68 m |
| 拜殿 | (0, −28)；9.00 × 7.66 × 6.10 m（沿用舊 waypoint 座標 0,−28；拜訪點 0,−21） |
| 手水舍 | (−11.5, −3)；2.90 × 3.19 × 2.64 m，朝 +x 參道 |
| 倉庫（小倉） | (16, −22)；4.54 × 4.18 × 3.87 m（明顯小於拜殿） |
| 賽錢箱 | (0, −22.7)；1.74 × 0.80 × 0.88 m，在拜殿正面石階前約 1.5 m（layout 設定值） |
| 狛犬 | (±2.7, −12.6)；石燈籠：春日一對 (±4.3, −19)、織部 (−7.2, −6.2)、雪見 (10.6, −31.2) |
| 後側池塘 | 中心 (12.5, −39.5)，橢圓半軸 7.5 × 5.0 m（長約 15 × 寬 10 m，旋轉 −20°，岸線另有不規則起伏）；水位 y＝7.82、最深 1.29 m；岸線坡度 0.23–0.58（不是水平淺灘） |
| 陰陽玉 | 池塘西岸扁石上 (4.65, −37.35)（LEVEL 3 彩蛋，全圖 1 顆） |
| 林徑 | 15 點坡腰路徑，半寬 1.1 m，切填出橫向平路（設計切 40°／填 33°）；庭院西緣 → 後山 → 北東端 (5.5, −52) |
| 植被 | 主樹 747 棵（22 種）＋下層 505、岩石 36、鋪石 67、飛石 16；櫻花 9 棵（染井吉野 5、山櫻 3、枝垂 1）混在闊葉／針葉林裡，不是粉白牆 |

## 3. 檔案清單

**場景／資料**
- `godot/maps/shrine_v2/shrine_v2.tscn`（總裝結果）、`gen/`（高度場 `height.f32`、遮罩、`layout.json`、`placements.json`、地形／遠景 mesh、`navmesh.res`、`sky_rig.tscn`…）
- `godot/data/shrine_v2.meta.json`（出生點、南端傳送區、出口）
- `godot/assets/shaders/shrine_terrain.gdshader`、`shrine_vista.gdshader`（獨立 shader，不動其他圖共用的）

**新製資產（Blender 5.2.1 → GLB → Godot）**
- `godot/assets/shrine_v2/src/make_shrine_props.py`＋`shrine_props_r3.blend`：**小倉、賽錢箱、掃帚**（含二つ巴徽章、「奉納」貼花，`src/tex/`）
- `godot/assets/shrine_v2/props/`（GLB、wrapper、mesh、komainu）、`kit/`（石階 kit）、`bld/`（拜殿／手水舍／鳥居 wrapper＋碰撞）、`mat/`

**沿用（未新製）**：拜殿、手水舍、博麗鳥居、陰陽玉（`assets/shrine/`，與 `D:\資產glb\博麗神社` 位元相同——這是建築與陰陽玉，不是樹）、狛犬造型（`assets/models/komainu_a.glb`，改石材）、石階 kit 的石材 mesh（抽自 `assets/_lod/{踏石,平台石,袖石垣,收頭石}.glb`）。

**生成管線與驗證腳本**（`godot/tools/shrine_v2/` 與 `godot/tools/verify_shrine_v2_*.gd`）：`layout.py`（配置單一來源）→ `gen_terrain.py`／`gen_placements.py` → `build_terrain.gd`／`build_buildings.gd`／`build_props.gd`／`build_kit.gd` → `build_scene.gd`（總裝，含導航烘焙）；`verify_placement.gd`、`verify_shrine_v2_{walk,stairs,story,camera,nav,wind}.gd`、`perf_probe.gd`、`deps_audit.py`、`record_walk.gd`。

## 4. 樹木來源（使用者要求：不採用 `D:\資產glb` 裡的樹）

- 實體樹只用 `assets/village_v2/veg_kit/trees`（專案內自製 LOD 樹）；`assets/landscape/` 的 Tripo 樹與舊遠景樹（`assets/vista/*`）整批排除，連同源副本都不用。
- 遠景／後山的「樹冠」是程序生成的林冠貼圖（`gen/canopy_far.png`），不是任何樹模型。
- 稽核（`tools/shrine_v2/deps_audit.py`）：場景相依閉包 **228 檔、缺檔 0**；禁用目錄（landscape／vista／_lod 樹／models 樹）命中 **0**；內文含「資產glb」字串的檔案 **0**；與 D 庫（267 檔）位元相同的只有 4 個——拜殿、手水舍、博麗鳥居、陰陽玉 GLB（皆非樹）。
- `verify_placement.gd` 另有「樹皆為 veg_kit」檢查，違規 0 棵。

## 5. 驗證結果（最終場景）

| 項目 | 方法 | 結果 |
|---|---|---|
| 擺放（接地／穿插／石階側牆／樹避讓／池岸） | `verify_placement.gd`，讀實際節點與網格頂點 | 26 項 PASS，`failures=0`。建築接地 gap −0.13..+0.07 m；石階側牆最大露出 0.25 m；鋪石頂面不被地形蓋住（最大 0.000 m）；水面不被土蓋住 |
| 真控制器實走（無頭） | `verify_shrine_v2_walk.gd`：南入口→石階 52 階→鳥居→手水舍→拜訪區→倉庫→池畔→拜殿後→櫻花林→林徑 6 點；回程沿林徑反向→庭院→鳥居→下石階→傳送區換圖到獸道 | 69 項 PASS，`failures=0`（連跑 2 次一致）。去程 264.8 m、遊戲時間 41.0 s |
| 真控制器實走（視窗、真 GPU） | 同上，`--print-fps` | `failures=0`；FPS 中位 103.5、p10 82、最低 79（去掉載入／換圖頭尾各 2 個取樣） |
| 劇情整合（MQ04 靈夢初見） | `verify_shrine_v2_story.gd`：真 main、真按鍵、真 Area3D、真對話與 StoryFlags | 29 項 PASS，`failures=0`：出生在南入口、指路指向參道→拜殿、靠近出現「[E] 拜訪」、對話 25 步、`met_reimu`、MQ04 完成→MQ07 開始、再拜訪進 repeat、候選圖↔獸道來回傳送 |
| NPC／AI 導航 | `verify_shrine_v2_nav.gd`：`NavigationRegion3D「導航」`（3928 多邊形） | 51 項 PASS，`failures=0`。9 條路線全找得到路（含入口→林徑北東端 148 m）；沿路徑每 0.25 m 放玩家同尺寸膠囊（r0.3 h1.7）重疊障礙 0；7 條無階梯路線用真 CharacterBody3D 代理走到終點；**全網格 3237 頂點／3928 重心 0 個與障礙重疊**；拜殿中央／池中央／界外都走不進去 |
| 風力 | `verify_shrine_v2_wind.gd`（視窗） | 樹 mesh 2988/2988 接線（闊葉高木 696、針葉 2004、闊葉小 284、枝垂 4、灌木 1515）；樹冠區畫面差：風開 5.147／風關 0.783（≥3 倍） |
| 第三人稱鏡頭 | `verify_shrine_v2_camera.gd`：300 個隨機站位×朝向×俯仰，共用的 CameraAdapter＋SpringArm3D | 新圖：視線被擋 0、彈簧臂縮成 0 的 0、鏡頭入碰撞體 7（2.3%）、鏡頭在地面下 2（0.7%）。**舊圖同一測法**：入碰撞體 10（3.3%）、地面下 1（0.3%）、縮成 0 的 1（0.3%）——同一個「肩偏 0.4 m 的射線彈簧臂」的限制，不是新圖特有 |
| 效能（GPU，5 個固定視角） | `perf_probe.gd`，視窗、RenderingServer 量測 | 新圖 9.7–11.8 ms（78–97 fps）：court_N 10.5、stairtop_N 11.2、stairmid_S 11.8、forest_W 9.7、aerial 9.3；舊圖 6.6–20.2 ms（aerial 20.2＝47 fps）。兩張圖用**同一組世界座標**的 5 個視角量，舊圖的建築與地形配置不同，所以只能看量級，不是同畫面對比。VRAM 686 MB（舊 1046 MB）。樹是最大開銷（關掉樹 court_N 降到 5.1 ms） |

**更正**：先前（壓縮前）曾記「court_N／forest_W 17 ms、54 fps」，那是探針的缺陷——地形沒有碰撞→地面射線打不到→相機座標 NaN→整張圖不裁切全畫。已修（`perf_probe.gd` 補地形 trimesh、遇 NaN 略過），上表為修正後數字；舊圖基準也重量了。

原始 log：`docs/shrine_v2/logs/`。

## 6. 視覺審圖（ART_REVIEW，非 ART_APPROVED）

總表：`shots/fin_sheetA–D.jpg`（A 南側參道→石階→鳥居→庭院；B 拜殿／賽錢箱／狛犬／手水舍／倉庫／池塘；C 林徑／後殿混交林／俯瞰／遠望；D 正交診斷）。實錄影片（真控制器沿去程路線走，Movie Maker 60 fps 固定幀率＝遊戲原速，1152×648，不入版控）：`_review/shrine_v2/video/shrine_v2_walk_36s.mp4`（前 36.5 s：南入口→石階→鳥居→庭院→拜殿東側→池畔→拜殿後→林徑；30 s 附近角色被前景樹幹局部遮住）、完整 41.6 s 版 `shrine_v2_walk_small.mp4`（最後約 5 s 角色被枝葉蓋住，見第 8 節第 9 點）。

審圖結論（17 張遊玩視角＋4 張診斷）：**無致命項**（沒有懸空石階、巨大垂直石牆、斷口、破面）。記錄在案、未再微調的**非阻斷**美術瑕疵：

1. 石階側邊石塊逐級外露、輪廓偏鋸齒，模組拼裝感偏強（fin03、fin05）。
2. 庭院夯土大面積偏均質、少踩踏／排水痕跡；石板亮度比土高約 +30 luma（實測石板 RGB≈(199,184,157)、土≈(175,151,121)，暖米色，不是青色）。
3. 俯瞰（fin16）有「碗狀」與「植被島」感，外圍山體紋理偏均質（程序林冠圖）；由南遠望（fin17）成立。
4. 林徑邊坡偏平滑（fin14）。
5. 陰陽玉小而不顯眼（LEVEL 3 彩蛋，刻意藏；若要更好找得另議）；池畔左側小叢植物看起來像立在乾地上（fin11）。
6. 鳥居／石階整體偏「正式」，偏僻感主要靠林相與距離撐。

## 7. 本輪修掉的真問題

- 倉庫旁柴棚、木箱×2、木桶、陰陽玉台石原本**沒有碰撞**（玩家會穿過去），已補（`_aabb_body`／`_convex_body`）。
- 導航網格踩過的坑與定案參數（寫在 `build_scene.gd::add_navigation` 註解）：①大網格要等非同步同步（~50 ms）才查得到；②`carve=true` 只挖出障礙腳印本身，路徑貼邊會卡 → 改 `carve=false`；③障礙柱體需向下延伸 1.2 m、最小邊長 0.5 m，否則陡坡／幼樹幹（r 5 cm）挖不出孔；④體素化後實際留白＝(⌈半徑/格⌉−1)×格，代理半徑 0.8 → 0.75 m；⑤輪廓簡化誤差 1.0 讓多邊形總數 3928 < 4096（`path_search_max_polygons` 預設），長路線的 A* 才不會被截斷；⑥最大坡 30°，NPC 走石階與林徑、不抄山坡（玩家 floor_max_angle 52° 仍可自行爬坡）。
- 實走測試的轉向器只在胸口高度（0.9 m）射線，看不見膝蓋高的賽錢箱／台石，回程直線切過去會頂住 → 回程改走林徑反向航點（真玩家會繞）。

## 8. 未解問題與限制（直說）

1. **尚未正式切換**。要換成正式 `shrine` 時，需處理（2026-10-22 盤點，不含候選目錄／工具／歷史封存檔）：`data/waypoints.json`（3 個目標＋邊界表）、`data/trail.meta.json`（connections＋傳送區 target）、`maps/trail/trail.tscn`（傳送區 metadata）、`data/mapRegistry.json`、`data/combat_spaces.json`、`data/shrine.meta.json`、`scripts/main.gd:321`、`scripts/ambience.gd:32`、`scripts/dev/review_start.gd:24`。建議做法＝**同 id 換內容**：舊 `maps/shrine/` 改名保留、候選場景與 meta（id 改 `shrine`）放進原路徑——waypoints 座標（0,40）／（0,−21）已與候選相容（劇情測試用記憶體重映證實），回退＝改名換回。需使用者先給 `ART_APPROVED`。
2. **NPC 自主生活系統**（`systems/npc_life`，格網烘焙 `*_walk.bin`）目前只為村莊建立，神社沒做；神社提供的是標準 `NavigationRegion3D`。
3. **導航的兩個使用須知**：①網格浮在地面上約 0.1–0.3 m（Recast 體素量化，實測 0.13–0.27 m），`NavigationAgent3D` 請設 `path_height_offset`；②用單純 `CharacterBody3D` 的代理**跨不過 0.16 m 的石階立面**（玩家有 `step_height 0.35` 上階邏輯，NPC 的 npc_life 是直接貼地擺放，不受影響）。
4. 鏡頭：共用彈簧臂在陡坡（林徑切坡、林地邊坡）偶爾讓肩偏的鏡頭點落進地形（0.7%）；新舊圖同一類限制，未動共用鏡頭裝置。
5. 效能數字是單機（GTX 1070）、固定 5 個視角＋一次完整實走；沒做長時間 soak、沒測其他顯卡。
6. 拜殿／手水舍／鳥居／陰陽玉沿用既有 GLB，**找不到對應的 Blender 原始檔**（未確認是否存在別處）；本輪明確有 Blender 原始檔的新製資產只有小倉、賽錢箱、掃帚。
7. 水面動態（流動／波紋）只在視窗截圖與實走中看過，沒有逐幀逐角度的長時間檢查。
8. `gen_placements.py` 被 `runpy` 當函式庫載入時**會重新生成**（確定性、同種子結果相同，但有寫檔副作用）。
9. **林徑北東端（約 x −9..6、z −48..−52）鏡頭被近景枝葉蓋住**：實錄影片最後約 5 s 角色被枝葉擋住（以影格中角色紅衣像素＝0 判斷）。veg_kit 的樹只有樹幹碰撞、沒有葉片碰撞也沒有近鏡淡出，彈簧臂不會因枝葉縮短。不是穿地或貼圖遺失；要根治得改林徑沿線的樹冠避讓（拉大路徑到大樹冠的距離）或讓近鏡葉片淡出，這輪未做。

## 9. 重現

```bash
# 以下在 godot/ 下；GODOT=D:/Godot/Godot_v4.7.2-stable_win64_console.exe
python tools/shrine_v2/gen_terrain.py && python tools/shrine_v2/gen_placements.py
$GODOT --headless --path . --script res://tools/shrine_v2/build_terrain.gd
$GODOT --headless --path . --script res://tools/shrine_v2/build_scene.gd        # 總裝＋導航烘焙（可加 --nav-eme= --nav-rad= --nav-part= 試參數）

$GODOT --headless --path . --script res://tools/shrine_v2/verify_placement.gd
$GODOT --headless --path . --script tools/verify_shrine_v2_walk.gd
$GODOT --headless --path . --script tools/verify_shrine_v2_story.gd -- --map=shrine_v2
$GODOT --headless --path . --script res://tools/verify_shrine_v2_nav.gd
$GODOT --headless --path . --script tools/verify_shrine_v2_camera.gd -- --map=shrine_v2 --region=-45,45,-58,66 --samples=300
$GODOT --path . --resolution 1280x720 --script res://tools/verify_shrine_v2_wind.gd            # 視窗
$GODOT --path . --resolution 1280x720 --script res://tools/shrine_v2/perf_probe.gd -- --views=<json>   # 視窗
python tools/shrine_v2/deps_audit.py
# 錄影（Movie Maker，60 fps 固定幀率）
$GODOT --path . --resolution 1920x1080 --write-movie <out.avi> --fixed-fps 60 --script res://tools/shrine_v2/record_walk.gd -- --map=shrine_v2
```
