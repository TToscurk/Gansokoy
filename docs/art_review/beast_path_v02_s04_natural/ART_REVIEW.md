# 獸道 V1.1：S04 BOSS 場自然化重製 — ART_REVIEW

> **狀態：ART_REVIEW，等待使用者審核。** 未 ART_APPROVED、未 git commit。
> 文中「AI 自評」是 vision 工具對截圖的讀法，**不是核准**；同一張圖重問分數會有 ±0.5 的浮動。
> 日期 2026-10-15｜範圍：僅 S04（S01–S03 只記錄，不施工）｜Godot 4.7.2、GTX 1070、Forward+｜V0.1 報告與截圖原樣保留在 `docs/art_review/beast_path_v01/`。

## 0. 結論

**可驗證的部分全過**：驗證 39 項（38 PASS + 1 INFO，0 失敗）；7 條真玩家實走 0 條未到達（含 S04 繞圈 148 m、東北出口平台）；S03｜S04 接縫位置／法線／顏色差皆為 0；四區地形碰撞形狀與 V0.1 逐位元相同。

**美術沒有達標**：十個必要鏡位 AI 自評平均約 **2.5／5**。人工石鋪、同心環、六石柱、方塊祭壇確定拿掉了；岩石的低多邊形切面感消失；瀑布與潭不再是白布與藍板。但「第一印象＝森林中的天然空地」**還沒做到**，被三件事拖住：

1. **V0.1 遺留的白模入口門**（雙石柱＋注連繩＋供物／白骨／石燈籠）與東北出口構件——在 13 張已審的最終圖裡有 11 張被點名為人工物；
2. **岩片連成一圈「岩牆」**，取代了林緣；
3. **地面中央偏均質、岩腳是連續的白灰碎石帶、落葉讀不出來**（權重量測 8%，肉眼 ≤ 2%）。

**效能**：S04 入口 -15.4%，超過規格的 10% 線。已做瓶頸隔離與一次岩石減量，沒有單一元兇（§9）；依停損規則，之後沒有再往上加料。

**一個非預期的副作用**：共用的森林規劃讓 S01–S03 的植被被重新抽樣（86% 的植被實例位置與 V0.1 不同）；地形／碰撞／水／道具則與 V0.1 相同（§5.5）。

需要你決定的事列在 §12。

---

## 1. 修改前後差異

| 項目 | 修改前（V0.1） | 現在（V1.1） |
|---|---|---|
| 地面 | 獨立 `ArenaPaving` 覆層：5,121 頂點／9,750 三角、離地 0.09 m；Voronoi 石板＋三道同心環（`arena_paving.gdshader`），白灰偏亮 | 沒有覆層。S04 地形網格自己用 `bp_ground.gdshader` 混合泥土／草土／落葉／碎石苔蘚 |
| 場邊構件 | 六根石柱、方塊祭壇、環紋 | 全部退役（layout 鍵改 `_retired_*`；gate 檢查不得殘留） |
| 岩片／巨石 | 6×6 細分方盒、平面著色；圓石取自共用的二十面體變體 | 172 個各自生成的自然岩石網格（圓角方盒→層理／脊線裂隙／起伏位移，平滑法線）＋`bp_rock.gdshader` 三平面 PBR |
| 瀑布 | 301 頂點漸層白幕＋泡沫盤 | 689 頂點水幕＋5 股主水束 shader、崖頂上游帶、落水薄霧與水珠粒子 |
| 潭／支流 | 單色藍水面 | 深度驅動水色、漣漪法線、破碎岸緣泡沫、落水泡沫環 |
| 森林 | 3,507 棵（S04：731） | 3,612 棵（S04：744）；S04 林緣不再被鋪石禁區推開 |
| 戰鬥空間／碰撞 | 直徑 40 m、坡度 ≤ 1.4° | 不變（§6） |

對照圖（左＝修改前，右＝最終；同鏡位、同時刻 10:00）：`compare/*.jpg`（18 張）；十個必要鏡位總覽：`final_10_views_contact_sheet.jpg`。

## 2. 修改過的程式與資產

| 類別 | 檔案（`godot/` 下） | 內容 |
|---|---|---|
| 生成器（修改） | `tools/beast_path/bp_lib.gd` | 移除環紋區塊；新增 S04 地表雜訊、`ground_channels()`、樹冠／岩腳場、瀑布濕岩帶 |
| | `forest_planner.gd` | S04 不再被鋪石禁區擋；`boss_floor`／破鳥居台地加明確圓形禁植區 |
| | `generate_beast_path.gd` | 移除 `ArenaPaving` 建立；S04 地形走 ground 模式；先寫岩／水材質；加粒子；印岩石統計 |
| | `layout_beast_path.json` | S04 `boss_floor`／破鳥居台地去掉 `paving`；`altar`／`rings`／`pillars` 改 `_retired_*`（保留歷史、程式不讀） |
| | `prop_builder.gd` | `make_slab` 改用 `rock_builder`；S04 巨石走 `_natural_rock`；岩片可視距離 190 m；小石不投影 |
| | `terrain_generator.gd` | ground 材質與頂點資料；岩／潭／支流／瀑布材質寫檔；新瀑布幾何 |
| | `verify_beast_path.gd` | 見 §7 |
| | `perf_beast_path.gd` | 加 `--only`／`--hide`／`--exp`（隔離量測；預設行為不變） |
| 新增工具 | `rock_builder.gd`、`fx_builder.gd`、`tps_shots.gd`、`probe_ground.gd` | 岩石網格建造、粒子、真玩家 TPS 擷取（含 `--hide` 隔離）、地表權重快探 |
| 材質（新增） | `assets/beast_path/materials/` `bp_ground.gdshader`／`.tres`、`bp_rock.gdshader`／`.tres`、`bp_water.gdshader`＋`bp_water_pool.tres`＋`bp_water_stream.tres`、`bp_waterfall.gdshader`／`.tres` | |
| 材質（退役） | `arena_paving.gdshader`（＋`.uid`）→ `materials/_retired/`，附 README 與 `.gdignore` | 沒刪除 |
| 產物（重生） | `maps/beast_path/{s01_entrance,s02_deep_forest,s03_crossroads,s04_boss_clearing,beast_path}.tscn`、`gen/s04_terrain.res`、`gen/forest_plan.json`、`gen/rocks/*.res`（172） | `[gen] 完成 10.6 s` |
| **沒有改** | `walk_beast_path.gd`、`make_shots.gd`、`render_plan.gd`、`inventory_beast_path.gd`、`probe_line.gd`；S01–S03 的 `*_terrain.res`；四區 `*_terrain_shape.res`；`data/beast_path.meta.json`（內容相同）；`village_v2`、`scripts/main.gd`、`data/mapRegistry.json`、玩家與相機 | |

完整檔案差異：`evidence/artifact_diff_vs_v01.txt`；最終版 sha256：`evidence/files_sha256.txt`。

**換行符**：我用 Python 編輯時把 6 個檔從 CRLF 轉成 LF（`bp_lib.gd`、`generate_beast_path.gd`、`prop_builder.gd`、`terrain_generator.gd`、`verify_beast_path.gd`、`layout_beast_path.json`）。這些檔都在未追蹤目錄、沒有 git 雜訊，Godot 兩種都吃；`forest_planner.gd` 保持 CRLF。

## 3. 石鋪 Shader 的處理

- **來源**：`arena_paving.gdshader` 是 Voronoi 石板＋三道同心環的程序 shader，掛在獨立的 `ArenaPaving` MeshInstance3D 上（V0.1 的 gate 量到 5,121 頂點／9,750 三角、離地 0.090 m）。
- **處理**：改的是生成器原始碼——`generate_beast_path.gd` 不再建立該節點，重新生成後仍然成立。shader 檔**沒刪**，移到 `materials/_retired/`（附 README、`.gdignore`）。
- **相依確認（今天重查）**：獸道範圍內只有 `verify_beast_path.gd`（檢查「不得殘留」的 gate）與 `make_shots.gd`（一個鏡位的標籤名 `w31_arena_paving`，不是節點引用）提到這個名字；`maps/beast_path`（含二進位 `.res`）、`assets`、`data` 無引用；`maps/village_v2`、`maps/slice`、`scenes`、`scripts`、`data`、`characters` 無引用 → 沒有被其他場景共用。
- **gate**：`arena.no_artificial_paving`（殘留節點 []、殘留 layout 鍵 []）、`arena.ground_material`。

## 4. 新地表材質設計

**來源**：專案已有的人間之里 P7 地面材質（7 層 CC0 貼圖陣列，`assets/village_v2/_matlib/ground/`），**唯讀引用，沒有改動村莊的任何檔案**。Blender 沒用到這一步。

**shader**：`bp_ground.gdshader`（196 行）。高度混合（`nrh.b`）讓土石交界不成直線；雙尺度取樣壓平鋪重複；岩層用三平面投影並用坡度修正岩權重（崖面 79°，純 XZ 投影會拉成條紋）；濕度壓暗＋降粗糙度；苔、葉色；崖面雨痕；S03 接縫用 `CUSTOM0` 的白模色淡出。

**頂點資料**：`COLOR`＝(壓實土, 礫, 泥, 岩)、`UV`＝(落葉林地, 濕度)、`UV2`＝(苔)、`CUSTOM0.rgb`＝白模頂點色；草＝1−其餘權重總和。

| 規格要求的材質 | 實作 |
|---|---|
| 乾燥壓實泥土 | 層 2（壓實土）：場中央與進場踩踏路 |
| 微濕深色泥土 | 層 4（泥）＋濕度壓暗：潭周邊、滲水處 |
| 草土混合 | 層 0（草，＝剩餘權重）：外圈與樹蔭外 |
| 枯葉林地 | 層 6（森林地表）：472 棵樹的樹冠投影下與林緣 |
| 苔蘚與石質過渡 | 層 5（岩，三平面）＋層 3（礫）＋苔：199 處岩腳 |

**分布邏輯**：每一類都有位置原因（樹冠遮陰→落葉、距岩腳→礫、水潭／滲水→濕泥、南口→踩踏路），再用方向性雜訊做瓣狀／舌狀邊界，不是均勻撒點。

**量測 vs 目視**：gate 在戰鬥圓（r≤20 m）內量到頂點權重 泥土 53%／草土 28%／落葉 8%／碎石裸岩 10%（目標「約」60／20／10／10；gate 範圍 48–74／10–32／4–20／2–14 是**我**對「約」的寬容解讀，不是你給的數字）。但 vision 讀截圖的比例是 泥土≈50%／草≈33%／碎石≈15%／落葉≤2%——**落葉在 TPS 距離讀不出來**，權重通過不代表視覺通過。

## 5. 岩壁、瀑布、水潭、森林

### 5.1 岩壁與巨石

- `rock_builder.gd`：立方體球→圓角方盒→多層位移（大起伏、層理進退、脊線裂隙、表面粗糙）→平滑法線；頂點屬性存苔、AO、層理色差、腳邊泥土。
- 172 個網格＝41 個崖岩片 POI ×（1 片主岩＋3 顆腳邊碎石，即規格 T04 的「岩壁腳邊崩落小石」）＋8 顆獨立岩石；種子＝節點 id，**每顆都不同**。總 111,672 三角（第一版 156,612，為效能降過一次）；位移後有 49 個三角（0.04%）局部折疊，沒有處理。
- `bp_rock.gdshader`：兩個尺度的三平面 PBR（與崖面地形同一層石頭）、層理明暗冷暖交替、垂直雨痕、瀑布附近整面濕暗、苔、腳邊泥土、暖色校正 ×(1.07, 1.0, 0.86)。
- 碰撞：用位移後頂點做凸包。
- **Blender 沒用**：T08 問「是否需要 Blender 做 Hero Rock」——這輪我用 Godot 內的程序化網格解決了「低多邊形切面」，沒有做 Hero Rock。Blender MCP 現在**可連線**（5.2.1 LTS、addon 1.8），要不要做由你決定（§12-7）。

### 5.2 瀑布

- 水幕貼崖面 0.30 m：13 欄×53 列＝689 頂點；gate `waterfall.on_face`：675 個（98%）離崖面 0.02–1.4 m、0 個在地形裡、14 個打不到。
- `bp_waterfall.gdshader`：5 股主水束（各自寬度與蛇行、水量隨高度起伏）＋股間稀疏碎白絲＋整體左右搖擺＋落口白邊＋底部增白；越往下水絲越快。
- 崖頂上游帶（第二個 surface，用支流水材質）；落水處薄霧 40 粒（alpha ≤ 0.06、80 m 外不畫）＋水珠 30 粒（55 m 外不畫），都沒碰撞、不投影。
- AI 自評（t05）：3／5。仍有的問題：中段有「白紗膜」感、底部是幾團白球。

### 5.3 潭與支流

- 水面仍是依地形裁切（gate `pool.shoreline`：934 個三角形裁切、水深 0.48 m、8 個方位中 7 個有岸；`pool.visible_from_arena`：3／3 取樣點通視）。
- `bp_water.gdshader`：深度驅動水色（淺處透泥底→中段→深處近黑綠）、兩個尺度的漣漪法線、破碎的岸緣泡沫、落水點泡沫環。
- AI 自評：水色不再是亮藍，但**深淺層次弱**、岸緣仍有斷續白線。

### 5.4 森林與林緣

- 3,612 棵（pin 17、樹 1,668、竹 317、下層 1,598、枯木 12）。S04：744 棵；S04 內距場中心 45 m 以內的植被 55→78、20–32 m 環帶 12→27（鋪石禁區拿掉後林緣可以貼近空地）。**不是單純加樹**：S04 總數只 +13。
- 戰鬥區用明確圓形禁植區保護；gate `arena.central_free`：r<14 m 613 個取樣點無碰撞物。
- AI 自評（t08）：2／5——草地直接接岩壁、缺灌木蕨類的過渡層。

### 5.5 S01–S03 森林被連動重抽樣（非預期副作用）

森林規劃共用一條隨機序列。拿掉 S04 的鋪石禁區後，序列後段的抽樣全變了，S01–S03 的植被被重新抽樣。以下數字取自 `forest_plan.json`（V0.1 備份 vs 現在）：

```
區       V0.1   V1.1     差         位置+樹種完全相同     相同比例   pin 固定樹(V0.1→V1.1)
S01      380    418   +38                61    16.1%   8→8
S02     1213   1316  +103                75     6.2%   4→4
S03     1183   1134   -49               244    20.6%   4→4
S04      731    744   +13                85    11.6%   0→0
S01–S03 合計相同： 380 ／ 2776
S01 新增 {'tree': 294, 'under': 63} ；消失 {'tree': 274, 'under': 45}
S02 新增 {'tree': 385, 'under': 851, 'dead': 5} ；消失 {'tree': 361, 'under': 772, 'dead': 5}
S03 新增 {'tree': 340, 'bamboo': 131, 'under': 416, 'dead': 3} ；消失 {'tree': 316, 'bamboo': 131, 'under': 489, 'dead': 3}
```

- **沒變的**：S01–S03 的地形 `*_terrain.res` 與四區 `*_terrain_shape.res` 位元相同；`data/beast_path.meta.json` 內容相同；S01–S03 的非森林節點（地形節點、碰撞、水、道具、標記）正規化資源 ID 後內容相同（S01 有 2 個資源條目因排序造成文字邊界差異，ext_resource 清單正規化後一致，25＝25）；pin（固定錨定樹）8／4／4 沒變。（`evidence/s01_s03_nonforest_identical.txt`）
- **變了的**：S01–S03 約 86% 的植被實例（樹、竹、下層、枯木）位置與樹種和 V0.1 不同（S01 +38、S02 +103、S03 −49）。不是碰撞退步（驗證與實走全過），但你在 V0.1 審過的 S01–S03 森林外觀跟現在不一樣。這等於違反了「不擴大到 S01–S03」的精神。處理選項見 §12-6。

## 6. 原有碰撞是否受影響

| 項目 | 結果 |
|---|---|
| 四區地形碰撞形狀（`*_terrain_shape.res`） | 與 V0.1 逐位元相同（高度場沒動；北崖 `cliff.face` 16.8 m／79° 與 V0.1 相同） |
| S04 視覺地形網格（`s04_terrain.res`） | 頂點資料改變（權重、UV、CUSTOM0），碰撞不依賴它 |
| 戰鬥區 | 直徑 40 m、r≤20 m 坡度最大 1.4°；r<14 m 613 點無碰撞物；繞圈 144 點被擋 0 |
| 南口 | 守門岩淨寬 11.9 m（V0.1：12.0 m）；岩壁最近內緣離中心 24.2 m（V0.1：24.9 m；要求 ≥ 21 m） |
| 岩石碰撞 | **改了**：位移後頂點的凸包取代舊盒／二十面體。第一次生成時 `arena.central_free` 失敗（`arena_cover_1` 的碰撞殼超進 r<14 m）；修法是縮小巨石尺寸係數（半寬 ≤ 1.06 r），**沒有放寬判準** |
| 純視覺物件 | 水幕、水面、粒子、地表細節都沒有碰撞 |
| 刻意被擋的兩處 | `lane_gate`（S03 回程巷盡頭）、`ExitSealBlock`（S04 出口封印）——gate 以此判 PASS，與 V0.1 相同 |

## 7. 驗證結果（39 項：38 PASS、1 INFO、0 FAIL）

在 `gen10` 最終場景上重跑（`evidence/verify_final_run.log`，JSON：`verify_report.json`）。

| # | gate | 結果 | 內容（取自 verify_report.json，截 118 字） |
|---|---|---|---|
| 1 | `limits.main_width` | PASS | 主路寬 3.50~5.00 m（限制 3.5~5.0） |
| 2 | `limits.branch_width` | PASS | 支線寬皆在 1.5~3.0 m |
| 3 | `limits.main_cross_slope` | PASS | 主路橫坡（中心↔路緣）最大 11.4°（要求 ≤ 15°） |
| 4 | `limits.boss_diameter` | PASS | 有效戰鬥直徑 40 m（限制 35~45） |
| 5 | `limits.arena_flat` | PASS | 戰鬥場（r≤20）坡度最大 1.4°，超過 6° 的取樣點 0/317 [] |
| 6 | `limits.scene_size` | PASS | 四區尺寸皆在建議值 ±25% 內 |
| 7 | `limits.bridge_clear` | PASS | 橋面 3.75 m，水面 1.95 m → 淨高 1.80 m（要求 1.0~2.5）；交角 77° |
| 8 | `scene.own_colliders_meta` | PASS | root meta own_colliders＝true 才不會被 main.gd 重複建 trimesh |
| 9 | `nodes.pois` | PASS | layout.pois 的節點都存在 |
| 10 | `nodes.markers` | PASS | 出生點／傳送／BOSS 觸發／出口封印／地形／水／森林節點齊全 |
| 11 | `nodes.static_bodies` | INFO | StaticBody3D 共 2269 個 |
| 12 | `seams.tiles` | PASS | S01／S02／S03／S04 接縫列：位置差 0.000000、法線差 0.000000、顏色差 0.000000 |
| 13 | `terrain.finite` | PASS | 地形頂點 NaN/Inf：0 |
| 14 | `ground.main_no_holes` | PASS | 主路 424 m 沿線每 0.5 m 向下射線：無地面 0 處 |
| 15 | `ground.main_steps` | PASS | 相鄰 0.5 m 取樣的行走面高差最大 0.18 m @ (-10,-211)（玩家 step_height 0.35，容許 +0.10）；超過 0 處；橋面等非地形碰撞命中 59 點 |
| 16 | `limits.main_grade` | PASS | 主路行走面最大縱坡（2 m 窗，含橋面）10.1°（限制 12°） |
| 17 | `ground.branches` | PASS | 四條支線沿線（排除出口封印／預留木戶）：無地面 0、高差超過 0.45 m 的 0 處  |
| 18 | `limits.branch_grade` | PASS | 支線行走面最大縱坡 13.3°（限制 16°） |
| 19 | `capsule.main` | PASS | 主路 848 個取樣點，玩家膠囊（r=0.3 h=1.7，離地 +0.35）沿線被非地形碰撞擋住：{  } |
| 20 | `capsule.branch.bamboo` | PASS | 168 點；擋住：{  }  |
| 21 | `capsule.branch.hollow_loop` | PASS | 160 點；擋住：{  }  |
| 22 | `capsule.branch.return_lane` | PASS | 77 點；擋住：{ "S03_Crossroads/Props/lane_gate/Col": [-26.8, -238.3, 38.0] } （盡頭刻意被 lane_gate 封住） |
| 23 | `capsule.branch.exit_shrine` | PASS | 67 點；擋住：{ "S04_BossClearing/Markers/ExitSealBlock": [32.2, -423.3, 11.0] } （盡頭刻意被 ExitSealBlock 封住） |
| 24 | `arena.central_free` | PASS | 戰鬥場中央 r<14 m 共 613 個取樣點，碰撞物：{  } |
| 25 | `arena.spawns_grounded` | PASS | PlayerSpawn_Arena 離地 0.10 m  BossSpawn 離地 0.10 m   |
| 26 | `arena.circling` | PASS | r=8/12 m 兩圈共 144 點可繞行，被擋 0 點 |
| 27 | `cliff.face` | PASS | 北崖（x=-8）：4 m 水平距離內最大落差 16.8 m（z=-439 起）、最陡 79°（要求 ≥ 12 m、≥ 65°） |
| 28 | `pool.shoreline` | PASS | 潭底 11.87、水面 12.35（水深 0.48 m）；8 個方位中 7 個在 2.5~8 m 內有岸（距離 4.8 4.8 5.8 6.0 6.3 8.0 5.3 ），缺口：["270°"]；水面依地形裁切 934 個三角形 |
| 29 | `pool.visible_from_arena` | PASS | 戰場出生點眼高 14.6 m → 潭面 3 個取樣點中 3 個視線通暢（要求 ≥ 2）；擋住的：[] |
| 30 | `waterfall.on_face` | PASS | 水幕頂點 689 個：離崖面 0.02~1.4 m 的 675（98%）、在地形裡 0、離崖太遠/打不到 14 |
| 31 | `arena.walls` | PASS | 崖岩片 41 片（東 17、西 21）；最近一片的內緣離戰場中心 24.2 m（平坦圓 r=22，要求 ≥ 21） |
| 32 | `arena.entrance_jaws` | PASS | 南口守門岩 JL／JR 淨寬 11.9 m（要求 6~16 m；主路寬 5.0 m） |
| 33 | `arena.no_artificial_paving` | PASS | S04 沒有鋪石覆層／環紋／場邊石柱／祭壇（殘留節點 []、殘留 layout 鍵 []） |
| 34 | `arena.ground_material` | PASS | S04 地形用 bp_ground.gdshader（材質 true；缺貼圖 []；頂點格式含 UV2／CUSTOM0：true） |
| 35 | `arena.natural_rocks` | PASS | S04 崖岩片／巨石 172 件全是自然岩石（外部網格＋bp_rock 材質＋法線＋頂點屬性）；總 111672 三角形；不合格 [] |
| 36 | `arena.water_materials` | PASS | S04 瀑布幕／潭面／支流都用 bp_waterfall／bp_water 材質（不合格 []） |
| 37 | `arena.ground_mix` | PASS | 戰鬥圓內 1257 個頂點：泥土 53%（要求 48–74）、草土 28%（10–32）、落葉 8%（4–20）、碎石／裸岩 10%（2–14）；苔覆蓋均值 0.06、濕度均值 0.00 |
| 38 | `trees.grounded` | PASS | 森林實例 3612 個，離地高度異常（> +0.15 或 < −0.9 m）0 個，最大偏差 0.65 m |
| 39 | `trees.match_plan` | PASS | forest_plan.json 3612 筆＝場景實例 3612 個 |

**驗證器相對 V0.1（35 項）實際改了什麼**（忽略換行符後 4 處，其餘判準與程式未動）：

1. 移除 `arena.paving_overlay`（檢查已不存在的石鋪覆層高度），新增 5 項：`arena.no_artificial_paving`、`arena.ground_material`、`arena.ground_mix`、`arena.natural_rocks`、`arena.water_materials` → 35 − 1 + 5 ＝ 39。
2. `seams.tiles`：S04 的 `COLOR` 現在存地表權重，所以接縫比對改讀 `CUSTOM0` 內的白模色；判準仍是「差異必須為 0」。
3. `waterfall.on_face`：上游帶搬到第二個 surface，所以頂點總數不再扣 95；閾值沒動。
4. 標題字樣。

碰撞、道路、膠囊、可達性、尺寸、岩壁、守門岩等 gate 的程式與閾值都沒動。V0.1 的 35／35 基準在 V1.1 開工前也重跑過：35 項 0 失敗、樹 3,507（`evidence/verify_v01_baseline_at_v11_start.log`）。

## 8. 七條真玩家實走

正式 `main.tscn`、真 CharacterBody、真輸入，在 `gen10` 最終場景重跑（`evidence/walk_final_run.log`；JSON：`walk_report.json`；`gen10` 之前那次的 `walk_report_pre_gen10.json` 一併保留）。**0 條未到達。**

| 路線 | 說明 | 結果 | 路點 | 實走 m | 最大上升 m | 終點 (x,y,z) | 與 gen10 前相同 | 與 V0.1 相同 |
|---|---|---|---|---|---|---|---|---|
| `main_fwd` | S01 起點 → S04 場內（沿主路 403 m） | **到達** | 69/69 | 403 | 12.38 | (4.1, 12.8, -374.9) | 是 | 是 |
| `main_back_sprint` | S04 → S01 起點（衝刺回程） | **到達** | 69/69 | 402 | 0.01 | (-0.8, 0.4, -13.0) | 是 | 是 |
| `branch_bamboo` | S03 竹林支線 | **到達** | 18/18 | 83 | 5.29 | (-49.8, 13.7, -324.9) | 是 | 是 |
| `branch_hollow_loop` | S02 迴圈支線 | **到達** | 17/17 | 79 | 0.59 | (20.0, 5.5, -173.7) | 是 | 是 |
| `branch_return_lane` | S03 回程巷（盡頭刻意被 lane_gate 封住） | **到達** | 9/9 | 35 | 0.00 | (-24.9, 7.1, -241.0) | 是 | 是 |
| `branch_exit_shrine` | S04 東北出口平台（盡頭刻意被 ExitSealBlock 封住） | **到達** | 4/4 | 10 | 1.01 | (30.9, 15.2, -421.8) | 是 | 是 |
| `arena_circuit` | S04 戰場繞圈（r=8／12 m，16 個路點） | **到達** | 16/16 | 148 | 0.49 | (18.6, 12.9, -410.2) | 是 | 是 |

- 「與 gen10 前相同」＝到達狀態、路點、實走距離、最大上升四項都相同；「與 V0.1 相同」同理。
- S04 繞圈 148 m、東北出口平台都到達。出口盡頭的 `ExitSealBlock` 是刻意常閉（出口封印解除屬 T25，未做）。

## 9. 效能

條件與 V0.1 相同：同一台機器、同一支 `perf_beast_path.gd`、GTX 1070、Forward+、關垂直同步。**同一個工作階段內交替量測 V0.1／V1.1 各 3 輪**（腳本臨時換入 V0.1 的 `maps/beast_path` 與材質，結束後用 sha256 驗證 V1.1 完整復原；`evidence/scripts/ab_perf.sh`）。

> 為什麼用交替而不是拿歷史數字比：同一份 V0.1 內容，歷史基準 S04 入口 105.6 FPS、場中心 102.5 FPS，這次工作階段量到約 90–98 與 88–94 FPS——機器狀態（別的 session 也在跑 Godot）本身就差 8–12%。

### 9.1 最終版（岩石緩解之後）

| 位置 | V0.1 三輪 FPS | V0.1 平均 | V1.1 三輪 FPS | V1.1 平均 | 變化 | draw call | 面數 k | 畫面物件 |
|---|---|---|---|---|---|---|---|---|
| `S02_corridor` | 64.3 / 62.8 / 62.0 | 63.0 | 61.5 / 59.8 / 58.8 | 60.0 | **-4.8%** | 3177→2982 | 4847→4865 | 9715→9736 |
| `S04_threshold` | 98.1 / 97.4 / 90.5 | 95.3 | 81.8 / 79.6 / 80.5 | 80.6 | **-15.4%** | 2653→2445 | 3537→3699 | 7005→6855 |
| `S04_arena_center` | 92.5 / 89.3 / 87.5 | 89.8 | 83.5 / 80.8 / 81.0 | 81.8 | **-8.9%** | 2812→2629 | 3613→3806 | 7280→7236 |

最差 **-15.4%**（S04 入口）。節點總數 22,081→22,649。

### 9.2 緩解之前（同樣的 A/B 做法，供對照）

| 位置 | V0.1 三輪 FPS | V0.1 平均 | V1.1 三輪 FPS | V1.1 平均 | 變化 | draw call | 面數 k | 畫面物件 |
|---|---|---|---|---|---|---|---|---|
| `S02_corridor` | 64.9 / 65.3 / 65.3 | 65.2 | 61.0 / 61.5 / 62.0 | 61.5 | **-5.6%** | 3177→3154 | 4847→5020 | 9715→9906 |
| `S04_threshold` | 97.5 / 98.1 / 97.2 | 97.6 | 81.7 / 82.4 / 82.3 | 82.1 | **-15.8%** | 2653→2576 | 3537→3872 | 7005→6986 |
| `S04_arena_center` | 93.4 / 93.2 / 93.7 | 93.4 | 83.2 / 83.5 / 83.2 | 83.3 | **-10.8%** | 2812→2772 | 3613→3988 | 7280→7379 |

緩解前最差 **-15.8%**（S04 入口）。岩石三角形從 156,612 降到 111,672、岩片加 190 m 可視距離、小石不投影之後，draw call 下降（S04 入口 2,576→2,445），**FPS 沒有可量測的改善**——代表瓶頸不在岩石幾何。

### 9.3 瓶頸隔離（只在 V1.1 上，單次量測，雜訊約 ±2–4%）

| 位置 | 把它關掉／換掉 | FPS 變化 |
|---|---|---|
| S04 入口 | 隱藏全部岩片與岩石（202 節點） | −1.6% |
| | 隱藏水面＋瀑布＋粒子 | −1.2% |
| | 隱藏 S04 地形網格 | +4.4% |
| | 地面換成單色簡單材質 | +2.9% |
| | 岩石不投影 | +1.7% |
| | 隱藏場中心 20–32 m 環帶的 27 棵樹 | +4.1% |
| | 隱藏全部森林 | +50.7% |
| | 森林不投影 | +33.8% |
| S04 場中心 | 隱藏全部岩片與岩石 | +4.5% |
| | 隱藏水面＋瀑布＋粒子 | −0.7% |
| | 隱藏 S04 地形網格 | +5.7% |
| | 地面換成單色簡單材質 | +3.7% |
| | 岩石不投影 | −0.5% |
| | 隱藏 27 棵環帶樹 | +0.5% |
| | 隱藏全部森林 | +10.6% |
| | 森林不投影 | +22.2% |

（原始輸出：`evidence/perf_iso1.log`、`perf_exp1.log`、`perf_exp2.log`。）

**解讀**：這輪新增或改動的項目（岩石、水與粒子、地面 shader、近場樹環）**沒有任何單一項目超過 6%**：地面 shader 約 3–4%、近場樹環與岩石各約 0–4%、水與粒子約 1%——加起來和量到的 −9～−15% 大致吻合，**成本是分散的**。表中 +50.7%／+33.8%／+22.2% 那幾列是整座森林與森林陰影，那是 V0.1 就有的全域成本，不是這輪新增的；它是整體最大的槓桿，但動它會影響 S01–S03 的外觀。

### 9.4 九個位置的單次量測（緩解之前，對 V0.1 歷史基準；僅供參考）

| 位置 | V0.1 歷史基準 | V1.1 單次（岩石緩解前） | 變化 |
|---|---|---|---|
| `S01_spawn` | 116.3 | 118.7 | +2.1% |
| `S01_torii` | 125.8 | 138.0 | +9.7% |
| `S02_forest_gate` | 65.9 | 62.8 | -4.7% |
| `S02_corridor` | 67.3 | 63.4 | -5.8% |
| `S02_bridge` | 64.0 | 62.8 | -1.9% |
| `S03_fork` | 81.3 | 79.2 | -2.6% |
| `S03_north` | 88.3 | 84.8 | -4.0% |
| `S04_threshold` | 105.6 | 88.8 | -15.9% |
| `S04_arena_center` | 102.5 | 86.8 | -15.3% |

S01、S02、S03 的變化落在約 −6%～+10%。S02 的 −2～−6% **不能單獨歸因於機器漂移**：V0.1 對照組在這個工作階段本身慢了 3–6%，但 S02 的植被實例也被重抽樣多了 103 個（+8.5%，§5.5）——兩個因素混在一起，我沒有再拆開量。

## 10. 最終實景截圖

全部來自 `gen10` 之後的最終場景（`final/`，1600×900、10:00、正式 `main.tscn` 的玩家 SpringArm 相機；`f*` 為自由攝影機）。**十個必要鏡位**（規格 T20）：

| # | 鏡位 | 圖 | AI 自評 | 主要問題 |
|---|---|---|---|---|
| 1 | BOSS 場南側入口 | [t01](final/t01_entrance_south.png) | 2 | 雙石柱＋注連繩＋垂紙像「結界門」；中央泥地帶過寬過淨；岩腳連續白灰碎石帶；落葉不明顯 |
| 2 | 入口看向中央 | [t02](final/t02_entrance_to_center.png) | 3 | 人工物突兀（木條、紅綠柱、繩布）；地面過平、分區生硬 |
| 3 | 中央地面近景 | [t03](final/t03_center_ground_close.png) | 3 | 偏均質的乾砂礫；缺乾濕／壓實的中尺度斑塊；落葉碎石像均勻撒點；中央辨識度好（4） |
| 4 | 中央向瀑布 | [t04](final/t04_center_to_waterfall.png) | 3 | 人工物破壞野趣；缺自然起伏與植被過渡；岩壁有層理但排列生硬 |
| 5 | 瀑布與水潭 | [t05](final/t05_pool_waterfall.png) | 3 | 水束可辨但中段有膜感；落水處底部幾團白球；潭面深淺差弱、岸緣斷續白線 |
| 6 | 北側岩壁 | [t06](final/t06_north_wall.png) | 2.5 | 「背景岩牆＋前排岩柱」；瀑布偏不透明；岩腳接地偏硬 |
| 7 | 戰場外圈樹林 | [t07](final/t07_outer_forest_east.png) | 2 | 連續岩牆取代林緣；灌木蕨類不足；林隙光弱 |
| 8 | 地面與森林過渡 | [t08](final/t08_ground_forest_transition.png) | 2 | 草地直接接巨岩壁；碎石成連續帶；落葉／樹根不明顯 |
| 9 | BOSS 出生位置 | [t09](final/t09_boss_spawn_player_view.png) | 3 | 戰鬥空間清楚；BOSS 站位與出口辨識弱；色塊邊界偏硬 |
| 10 | 進場道路回望 | [t10](final/t10_look_back_to_road.png) | 2 | 入口雙柱＋繩像關卡門；岩牆主導、近場樹少 |

平均約 **2.55／5**。

**補充鏡位**：[t11 東北出口](final/t11_ne_exit.png) 3（出口通道可辨但平台不突出；紅柱、黑橫梁、倒桿像簡易幾何）｜[t12 S03｜S04 接縫](final/t12_seam_s03_s04.png) **4**（沒有接縫線、裂縫、懸空，樹沒在接縫處中斷）｜[f04 高空俯瞰](final/f04_arena_aerial.png) 3（近橢圓、南側收窄，但岩牆過度封閉、中心泥地—外圈草石的環帶感太明顯）｜[t13](final/t13_west_wall_altar.png)、[f01](final/f01_waterfall_closeup.png)、[f02](final/f02_pool_surface.png)、[f03](final/f03_cliff_overview.png)、[f05](final/f05_ground_macro.png) 為 gen10 最終版，但**沒有逐張做 AI 評審**（f01／f02 只在 gen10 之前的中間版本審過）。

`work/` 是開發途中的中間輪次截圖（r1–r5、iso），不是最終成果。

### T21 驗收表（AI 自評）

| 項目 | 必須達成 | 現況 |
|---|---|---|
| 第一印象 | 森林中的天然空地 | **部分**：先像「有結界入口的岩谷競技場」 |
| 地表 | 以泥土、草、落葉為主 | **部分**：泥土＋草成立；落葉讀不出；中央偏均質 |
| 人工感 | 沒有完整石環與大型人工鋪地 | **達成**（石環、鋪地、石柱、祭壇已移除）；但 V0.1 白模入口門與出口構件仍在 |
| 岩壁 | 不像整排同款幾何方塊 | **部分**：切面感消失；但連成岩牆 |
| 瀑布 | 不像純白布幕 | **部分**：有主水束與碎絲；中段膜感、底部白球 |
| 水潭 | 不像藍色塑膠板 | **部分**：灰藍偏暗綠、有漣漪；深淺層次弱 |
| 植被 | 分布自然、不等距 | **部分**：不等距；林緣中低層不足 |
| 戰鬥 | 中央空間充足 | **達成**：40 m、≤1.4°、無碰撞物、繞圈 148 m |
| 視線 | BOSS 與主要出口可辨識 | **部分**：潭 3／3 通視；BOSS 站位與出口辨識弱 |
| 性能 | 沒有不可接受的下降 | **部分**：S04 入口 -15.4%、場中心 −9%、S02 −5%；仍約 80 FPS（S04 入口）、約 59–62 FPS（S02） |
| 世界觀 | 符合幻想鄉普通野外林道 | **部分**：白模入口門讓它偏「結界／關卡」 |

## 11. 完成／未完成／受阻

**已完成且驗證**
- 生成完整：`[gen] 完成 10.6 s`，四區＋根場景＋meta 皆 OK，時間戳在同一次 10 秒內；`maps/beast_path` 186 檔與 A/B 前後快照 sha256 一致。
- 人工石鋪／同心環／六石柱／方塊祭壇移除（gate＋前後對照圖）。
- 天然地表 shader 與權重（`arena.ground_material`、`arena.ground_mix`）。
- 172 個自然岩石（`arena.natural_rocks`）；水／瀑布材質（`arena.water_materials`）。
- 碰撞、道路、可達性：39 項驗證；7 條實走；148 m 繞圈；東北出口平台。
- S03｜S04 接縫（gate 差 0＋ t12 目視）。
- 舊 shader 無引用（§3）。
- 效能 A/B 三輪（§9）。

**已完成但尚未驗證**
- 動態表現：瀑布水束、潭面漣漪、霧與水珠粒子只看過靜態截圖，沒有影片或連續幀檢查。
- 只在 10:00 的光照審圖（沒看清晨、黃昏、夜間）。
- BOSS 戰實戰時相機 SpringArm 與岩壁／樹的遮擋——只做了靜態 TPS，沒有實戰。
- 其他硬體：只在 GTX 1070 上量。
- 49 個折疊三角形（0.04%）的肉眼影響。

**尚未完成**
1. **V0.1 白模道具的正式資產化或移除**：入口 `pillar_L/R`（約離中心 35 m）、`shimenawa_threshold`、`offerings_threshold`、`bones_threshold`、`arena_lantern_0/1`；東北出口 `exit_pillar_L/R`、`exit_shimenawa`、`arena_torii_broken`、`ExitSealBlock`（清單：`evidence/s04_props_inventory.txt`；外層容器節點座標在原點，距離欄位對它們無意義）。
2. 連續「岩牆」重排（T06：避免邊界物件平均排列）。
3. 地表第二輪：中尺度乾濕／壓實斑塊、岩腳碎石改崩積扇而非連續帶、落葉讀得出來。
4. T04 的**立體**地表細節（落葉堆、碎枝、小碎石、裸露樹根）沒做——目前只有 shader 層級的葉色與礫層；樹根只有 V0.1 遺留的 `arena_roots_0..3` 裝飾根。
5. 林緣中低層（灌木、蕨類）。
6. 瀑布底部白球與中段膜感；潭面深度。
7. 效能超過 10%（S04 入口）。
8. S01–S03 森林配置未凍結（§5.5）。
9. 依規格**不在本輪範圍**：BOSS 戰鬥邏輯、出口封印解除（T25）、navmesh、V2→獸道傳送——都沒動。

**受阻（外部依賴）**
- 沒有硬性阻塞。Blender MCP 現在可連線，V1.1 沒用它；Hero Rock／正式 POI 資產等你決定。
- 陰影面偏冷（量到陰影崖面約 (59,72,87)）——**推測**來自共用的天空環境光（DayNight），沒有做隔離驗證；我只在岩石與崖面材質加了暖色補償，補償後沒有重新量化。

## 12. 需要你決定的事

1. **入口門與出口構件（V0.1 白模）**：A 全部移除，改用岩體錯位、倒木、踩踏痕引導；B 保留「結界」敘事但降到最弱（只留注連繩，拿掉供物／白骨／石燈籠，雙柱換成枯木或自然岩）；C 用 Blender 做正式資產。AI 的看法：A 或 B——13 張已審圖中有 11 張點名它，而規格 T06 說「沒有明確敘事功能者優先移除」。
2. **岩牆**：維持，或重排 W／W2／E／E2 弧（拉出 3–5 個缺口、岩群化、降部分高度、讓樹蕨進場）。這會動 `arena.walls`、碰撞，需要重生成＋驗證＋重走（我不會放寬 ≥ 21 m 的內緣判準）。
3. **地表第二輪**：授權與否（shader 的中尺度變化＋權重改碎石分布＋少量立體落葉／樹根）。我建議限定一輪，做完仍不行就停。
4. **瀑布／潭第二輪**：底部白球改成單一泡沫盤＋低霧、潭面加深度層次。
5. **效能**：接受 S04 入口約 80 FPS；或授權優化（候選：ground shader 改單尺度取樣約 +3%、近場樹環的影子／LOD 最多 +4%、全域森林陰影設定最大槓桿但會影響 S01–S03 外觀）。
6. **S01–S03 森林**：接受重抽樣；或要求凍結——改生成器讓 S01–S03 載入 V0.1 凍結的 plan、S04 單獨規劃（需重生成＋重驗證＋重走）。V0.1 的 plan 備份在 `scratch/bp_backup_v01`（不在專案內，若要採用我會先把它存進專案）。
7. **Blender**：Hero Rock 與正式 POI 資產要不要用。

## 13. 過程備註

- **審批阻擋**：中途一個合併的唯讀檢查指令被審批擋下（1000 秒未回應），我沒有重試或改寫繞過；你授權後拆成獨立小指令，行程列舉、`ls`、`grep`、`find` 都沒有再觸發審批，所以我不確定當初是哪一段觸發的。
- **其他 session**：檢查時有別人的 headless Godot 在跑 `tools/p13/w9/w9r2_prefab.gd`（人間之里 P13 W9，PID 11732／19040），命令列與獸道無關；我沒有動它。另有 Blender 5.2.1（PID 4148）與 MCP 橋接行程，也沒動。
- **`.uid` 檔**：`materials/` 多了 3 個 `.gdshader.uid`（`bp_rock`／`bp_water`／`bp_waterfall`），`tools/beast_path/` 多了 `fx_builder.gd.uid`、`rock_builder.gd.uid`。它們是 13:14:03 同一秒建立的；12:45:52（我最後一張最終擷取）到 14:03 之間我沒有啟動任何 Godot，所以不是我的腳本產生的；同一秒別人的 `tools/p13/w9/w9r3_joint_probe.gd` 也多了一個 `.uid`，推測是某個 Godot 專案掃描。內容是 20 位元組的 ID，無害，我沒刪。其餘 14 個材質檔與快照 sha256 一致。
- **git**：分支 `yoriichi-combat-and-village-routing`，HEAD 已被別的 session 推到 `b673ee1`；獸道範圍（tools／assets／maps／meta／兩個 art_review 目錄）在 git 全是未追蹤，沒有已追蹤檔被改；範圍外有 1,233 筆變更是別人的。`main.gd` 與 `mapRegistry.json` 在 git 顯示為已修改，但 mtime 是 10-03 與 09-22，早於本 session，不是我改的。**沒有 commit。**
- **V0.1 紀錄**：`beast_path_v01/` 的三份報告 JSON 與修改前備份逐位元相同，沒被覆蓋。
- 每次擷取都有一行 `ERROR: Condition "hr != ..." ERR_CANT_OPEN`，是本機音訊裝置初始化失敗，與畫面無關。
- **修改前備份**：`C:/Users/B365/AppData/Local/hermes/cache/scratch/bp_backup_v01/`（scratch，不在專案內）。

## 14. 重現指令

`godot` ＝ `D:/Godot/Godot_v4.7.2-stable_win64_console.exe`，工作目錄 `godot/`。

```
# 生成（約 11 s，headless；會重生全部四區）
godot --headless --path . --script res://tools/beast_path/generate_beast_path.gd
# 驗證（headless）
godot --headless --path . --script res://tools/beast_path/verify_beast_path.gd -- --out=<json>
# 7 條實走（需顯示器，約 3 分鐘）
godot --path . --script res://tools/beast_path/walk_beast_path.gd -- --map=beast_path --out=<json>
# TPS 擷取（需顯示器；--hide 可隔離渲染找穿幫來源）
godot --path . --script res://tools/beast_path/tps_shots.gd -- --map=beast_path --out=<dir> --hour=10 [--only=a,b] [--hide=名稱,meta:鍵|另一組]
# 效能（需顯示器；--hide／--exp 隔離量測）
godot --path . --script res://tools/beast_path/perf_beast_path.gd -- --map=beast_path --out=<json> [--only=...] [--hide=...] [--exp=rock_shadow_off,cheap_ground,forest_shadow_off,ring_hide]
```

## 附：審圖資料夾索引

| 路徑 | 內容 |
|---|---|
| `final/` | 最終 18 張實景（t01–t13、f01–f05） |
| `compare/` | 修改前後並排 18 張；`../final_10_views_contact_sheet.jpg` 為十個必要鏡位總覽 |
| `before/` | 修改前：`tps/` 18 張、`v01_reports/` 三份 V0.1 JSON |
| `verify_report.json`、`walk_report.json`、`walk_report_pre_gen10.json`、`perf_report_run1.json` | 驗證／實走／早期效能結果 |
| `ab/` | 最終版 A/B 各 3 輪 JSON；`ab/pre_mitigation/` 緩解前 A/B |
| `evidence/` | 生成／驗證／實走／效能日誌、S01–S03 差異分析、道具清單、檔案差異與 sha256、腳本 |
| `work/` | 開發途中的中間輪次截圖 |
