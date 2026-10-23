# 獸道 V0.1 白模 — ART_REVIEW

**狀態：ART_REVIEW（白模，非最終美術）。未 ART_APPROVED、未封存、未 commit。**
日期：2026-10-15　依據：`docs/獸道_完整開發規格書_V1.0.md`、`docs/reference/獸道概念圖/{獸道概念圖1,2,3,林道}.png`

---

## 1. 這是什麼

由人間之里（南）往北的一整條山林關卡，白模可跑：**入口林道 → 中段密林＋溪橋 → 岔路與遺跡 → 獸王之域（BOSS 場）**，另有 3 條支線與 1 條戰後出口。
座標 1 單位＝1 m；+X 東、+Z 南、+Y 上；主路往北（−Z）。地圖 220 × 520 m，主路 424 m。

| 區 | 內容 | 概念圖對應 |
|---|---|---|
| S01 入口林道 | 田緣路、農舍＋田畦、柵欄；朱紅鳥居＋一對石燈籠＋入口小祠＋路標；櫻樹草地 | 概念圖 1/2/3「入口林道」 |
| S02 中段密林 | 林緣門樹、杉木走廊、樹根/樹樁/抓痕/腳印；巢穴側環（供品/獸骨/菇）；下坡石階＋**木橋 8.6 m 跨主溪**＋踏石＋上游小瀑；根階與古木巨岩隘口 | 「中段林區」「溪流木橋」「巨木與岩石區」 |
| S03 岔路與遺跡 | 林間空地＋苔石燈籠＋路邊小祠＋三向路標；**竹林支線**（石階、苔岩、小鳥居＋左右石燈籠）；返回捷徑（預留木戶）；北行暗林（注連繩、損毀柵欄、傾倒燈籠） | 「分岔路」「竹林方向支線」「分岔與遺跡」 |
| S04 獸王之域 | 結界石柱＋注連繩 → **守門巨岩隘口** → 近圓石鋪戰場（有效直徑 40 m，三道同心環帶）；北側 **16.8 m 近垂直岩崖＋瀑布＋水潭**；環形岩壁；紅葉古樹；破損鳥居高台＝戰後出口；祭壇、斷柱 | 「深處・獸之領域」「瀑布與巨岩」「破損的鳥居與社跡」 |

支線：`bamboo`（83 m）、`hollow_loop`（80 m）、`return_lane`（預留木戶）、`exit_shrine`（出口，目前以注連繩石柱＋隱形擋塊封住）。

## 2. 數量（`tools/beast_path/inventory_beast_path.gd` 實測）

| 項 | 數 | | 項 | 數 |
|---|---|---|---|---|
| 森林實例（總） | 3,507 | | 鳥居 | 3 |
| ├ 樹 | 1,599（杉 686、楢 242、紅葉 167、欅 105、椎 104、檜 94…） | | 石燈籠 | 8 |
| ├ 竹 | 317 | | 石柱（含 6 根場邊斷柱） | 10 |
| ├ 林下（蕨/灌木/笹/躑躅） | 1,562 | | 崖岩片 | 41 |
| ├ 枯木 | 12 | | 岩石 | 20（+3 組散落） |
| └ 釘點樹（手放） | 17 | | 柵欄 | 9 |
| CollisionShape3D | 2,327 | | 木橋／石階／踏石 | 1／4／2 |

森林一律**重用** `assets/village_v2/veg_kit` 與 `bamboo_kit` 的 prefab（不另做樹）；其餘道具是程序白模代理（`bp_kind`／`bp_spec` 帶規格書資產 ID，之後換 Blender 資產時對得上）。

## 3. 驗證（全部是量真物理，不是「程式沒報錯」）

`verify_beast_path.gd`（headless，載入真場景，射線＋玩家膠囊）：**35 項、0 失敗**，exit 0。報告：`verify_report.json`。

- **規格上限**：主路寬 3.5–5.0 m ✓、支線寬 1.5–3.0 m ✓、主路縱坡 10.1°（≤12°）、支線 13.3°（≤16°）、主路橫坡 11.4°（≤15°）、橋面淨高 1.80 m（1.0–2.5）、戰場有效直徑 40 m（35–45）、戰場 r≤20 最大坡 1.4°（≤6°）、四區尺寸皆在建議值 ±25% 內。
- **地面連續**：主路每 0.5 m 向下射線，無洞、相鄰高差最大 0.18 m（玩家 step_height 0.35）；四區地形接縫位置/法線/顏色差 0.000000。
- **玩家膠囊沿線掃描**（r 0.3、h 1.7）：主路 848 點、支線 472 點，除了兩個刻意的封口（預留木戶、出口封印）外**沒有任何非地形碰撞物擋路**；戰場中央 r<14 m 無碰撞物、r=8/12 兩圈共 144 點可繞行。
- **BOSS 場景觀**：北崖 4 m 水平距離內落差 16.8 m、最陡 79°；水潭有岸（8 方位 7 個，缺口＝支流出口）；**戰場出生點眼高看得到潭面 3/3**；瀑布幕 301 頂點中 97%（293 個）離崖面 0.02–1.4 m、0 個在地形裡；崖岩片 41 片、最近一片內緣離戰場中心 24.9 m；南口守門岩淨寬 12.0 m；石鋪覆層 0 個三角形沉入地形。
- **森林**：3,507 個實例離地高度異常 0 個；`forest_plan.json` 3,507 筆＝場景 3,507 個。

`walk_beast_path.gd`（正式 `main.tscn`、真 `CharacterBody3D`、真輸入 `move_forward`／`sprint`）：**7 腿全到達、0 卡住**。報告：`walk_report.json`。

| 腿 | 結果 |
|---|---|
| 主線 S01→BOSS 場入口（走） | 403 m、最大上升 12.38 m |
| 主線返回出發點（**衝刺**） | 402 m |
| 竹林支線／巢穴側環／返回捷徑／出口 | 83 m／79 m／35 m／10 m（後兩者走到封口前） |
| **BOSS 場繞圈**（中心→r=12 一圈→回中心→東北出口平台） | 148 m、最大上升 0.49 m |

## 4. 效能基準（只量，不最佳化；GTX 1070、Forward+、關垂直同步）`perf_report.json`

| 位置 | FPS | draw call | 面（k） |
|---|---|---|---|
| S01 出生點／鳥居 | 116／126 | 1,912／1,742 | 2,486／2,555 |
| **S02 林帶（最低）** | **64–67** | 2,290–3,135 | 3,556–5,104 |
| S03 岔路／北行 | 81／88 | 3,137／3,013 | 4,785／4,837 |
| S04 戰場入口／中心 | 106／103 | 2,531／2,655 | 3,459／3,493 |

森林是**逐棵 prefab 實例**（尚未 MultiMesh／LOD 合批）。沒有災難性問題（無卡頓、無載入失敗），一般 debt 記為 T27，不在本輪做。

## 5. 實景審圖（`shots_f/`，40 張；`shots_f.json` 是鏡位）

分數是我用視覺模型逐張審的**自評**（1–5），不是 ART_APPROVED；「進步」欄是和同一鏡位上一版相比。

| 鏡位 | 分 | 重點 |
|---|---|---|
| `w18b_arena_wide_n` BOSS 場朝北廣角 | 3.5 | 骨架成立：圓形石鋪、環帶、岩壁、瀑布、秋色大樹；不再是「林間空地」 |
| `w17_arena_reveal` BOSS 入口第一眼 | **4** | 雙岩夾口→開闊戰場成立，遠景崖/瀑布/紅葉樹都在 |
| `w31_arena_paving` 石鋪低角度 | **4**（上一版 3） | 石縫變細後板塊仍清楚，環帶（小石板、偏冷）可辨 |
| `w29_arena_wall_west` 西側岩壁 | 3.5（上一版 2） | 由「一排同款方塊」變連續崖壁，有高低、斜傾、岩腳碎石 |
| `w32_pool` 水潭近景 | 3（上一版 2） | 水面／岸線清楚，瀑布接入潭；落水泡沫弱 |
| `w25_bamboo_end` 竹林盡頭 | **4** | 小鳥居＋左右石燈籠＋密竹＋重陰影 |
| `w03b_torii_close` 入口鳥居 | 3 | 鳥居/燈籠一對/柵欄/小祠成立；仍偏公園感 |
| `o_full_north` 全覽 | 3 | 山谷起伏與疏密成立，段落順序在俯瞰下不夠醒目 |

## 6. 已知缺口（non-blocking，留給美術階段；我在此停手，不再磨）

1. **入口林道偏「公園感」（3/5）**：路緣過渡（落葉/碎石/樹根）不足，右側林帶不夠貼近。S01 密度本來就刻意低（村緣→林），再加密需要你定調。
2. **水與瀑布是白模材質**：沒有水 shader／泡沫與飛沫粒子；瀑布頂缺崖口造型。
3. **崖面與岩片是程序低模**：層理是頂點色、不是真地質結構；最終資產建議用 Blender 重做（Blender MCP 9876 目前**連不上**，這輪也沒用到）。
4. **石鋪是 shader 覆層**（不是實體石板）；近景石縫仍偏均勻。
5. **石燈籠/小祠/路標是方塊代理**（石燈籠燈室沒有開孔）。
6. **森林未合批**（見 §4）。
7. **玩區內 >40° 的 258 格（2.2%）全部在 S04 北崖**（最陡點 (−38,−440)＝崖線）：刻意的不可走崖壁，不是錯誤。
8. 本地音訊裝置警告（WASAPI）與地圖無關。

## 7. 銜接與待你裁定

- **V2→獸道 傳送**：`village_v2.meta.json` 由你先前裁定停用（P11 R2B），本輪**沒動**；獸道端 `Portal_Village`（x0, z6 → `village_v2`）已備好。
- **戰後出口／竹林出口**：meta 的 portal `target` 留空（預留）；出口封印（`ExitSealBlock`）的戰後解除邏輯未接（規格 T25）。
- **BOSS 觸發節點**（`BossTrigger`／`BossSpawn`／`PlayerSpawn_Arena`）已放且貼地，**戰鬥邏輯、敵人、音樂、HUD 未做**。
- `data/mapRegistry.json`、`scripts/main.gd` 未改（`--map=beast_path` 現在就能載入；正式入口要註冊與你的裁定）。
- 另一個 session 同時在改 `village_v2`（P13 W9，`village_v2.tscn` 02:35 有變更）；本輪對 `maps/village_v2`、`trail`、`main.gd` 的寫入為 0（所有寫入點限 `maps/beast_path/`、`data/beast_path.meta.json`、審圖資料夾；`village_v2` 只被當唯讀植被來源引用）。

## 8. 重現

```bash
cd godot
GD="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
$GD --headless --path . --script res://tools/beast_path/generate_beast_path.gd      # 生成（~10–18 s）；唯一資料來源 tools/beast_path/layout_beast_path.json
$GD --headless --path . --script res://tools/beast_path/verify_beast_path.gd        # 35 項驗證，exit 0 才算過
$GD --headless --path . --script res://tools/beast_path/walk_beast_path.gd -- --map=beast_path --scale=4   # 真玩家實走 7 腿
$GD --path . --script res://tools/beast_path/perf_beast_path.gd -- --map=beast_path                         # 效能（需顯示）
# 審圖：make_shots.gd 產鏡位 JSON，再 $GD --path . -- --map=beast_path --shots=<json> --shotdir=<dir>
```

**注意**：改 layout 後一定先確認 generate 印出 `[gen] 完成` 且四個 `.tscn` 時間戳更新，再跑 verify——生成器解析失敗時 verify 仍會跑，驗的是舊場景。

## 9. 檔案

- 生成/驗證工具：`godot/tools/beast_path/`（`layout_beast_path.json`、`bp_lib.gd`、`terrain_generator.gd`、`prop_builder.gd`、`forest_planner.gd`、`generate_beast_path.gd`、`verify_beast_path.gd`、`walk_beast_path.gd`、`perf_beast_path.gd`、`make_shots.gd`、`render_plan.gd`、`inventory_beast_path.gd`、`probe_line.gd`）
- 產物：`godot/maps/beast_path/`（`beast_path.tscn`＋`s01…s04`＋`gen/*.res`、`gen/forest_plan.json`）、`godot/data/beast_path.meta.json`
- 材質：`godot/assets/beast_path/materials/arena_paving.gdshader`
- 審圖：本資料夾（`plan_base.png`、`profile.txt`、`shots_f/`、`verify_report.json`、`walk_report.json`、`perf_report.json`）
