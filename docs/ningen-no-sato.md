# 人間之里 —— 總結（街區重構完結，2026-08-06）

**這份文件是什麼**：人間之里這一整輪（15 個小輪次）做完之後的**查詢用參考**。
現況、管線、不可違反的規則、復發性病症、未結項目，按主題排，不按時間排。

**這份文件不是什麼**：不是工作日誌。「當時為什麼這樣決定」在
`ningen-no-sato-redesign.md`（開工規格 + 15 輪的逐輪紀錄，924 行），
那份留著當歷史，有爭議時翻它。這一份是「我現在要動這張圖，該知道什麼」。

---

## 1. 現況速查

| | |
|---|---|
| 地圖 | `godot/maps/village/village.tscn`（`playSize` 460×460、地形 600×600） |
| 產生器 | `godot/tools/gen_town.gd`（3,429 行，`MAP_ID := "village"`） |
| 節點數 | 1,450 |
| 種子 | `SEED := 20260806`（各層另有自己的偏移，見 §4） |

**內容清單**（產生器的 audit 逐行印出，改東西時對這張表）

| 層 | 量 | draw call |
|---|---|---|
| 町家 | 169 棟 / 5 種模組・0 穿插 | 5 |
| 地標 | **真內容 6 座、佔位 0 座** | — |
| 地標塔 | 3 座（tower_fire / bell / mill） | 3 |
| 橋 | 3 座（主橋 12m + 小橋 ×2），全帶 `needs_trimesh` | 3 |
| 護岸 | 115 段 | 1 |
| 門樓 | 2 座（北門・西南門） | — |
| 石溝 | 202 節（28 節是橫街覆蓋段） | 3 |
| 街燈 | 21 盞（各帶 OmniLight3D） | — |
| 密度層 | 暖簾 21・提灯 21・招牌 9・地面雜物 68・花樹 61 | 11 |
| 水邊生物 | 鴨 9・鯉 14・鷺鷥 5 | — |
| 水生植物 | 睡蓮 220・荷 80 | 2 |
| 稗田邸（完整獨立版） | blockout 22,600 面 + 植栽 136 實例 | 1 + 10 |
| 稗田邸緩衝疏林 | 46 株（保留區外緣 3~9m 環帶） | 3 |
| 草層 | 23,881 叢（Shrubs/Ferns/GrassTall/GrassFlower/Reeds） | 5 |

**六座地標**（`LANDMARKS`，全部已搬入真內容、**沒有任何佔位碰撞箱**）

| 地標 | 中心 | 保留區 | 實測幾何跨度 |
|---|---|---|---|
| 寺子屋 | (−26, −52) | 28.4 × 19.8 | 27.5 × 18.8 |
| 鈴奈庵 | (11.6, −52) | 12.8 × 15.0 | 11.9 × 14.7（整棟轉 −90°） |
| 鎮守之杜 | (−26, 2) | 42.9 × 36.0 | 36.5 × 33.6 |
| 市場 | (−26, 57) | 37.2 × 34.0 | 36.3 × 26.8 |
| 足洗邸 | (26, 112) | 38.5 × 33.6 | 38.4 × 32.9 |
| 稗田邸 | (−80.5, −195.8) | 97.0 × 118.5 | 96.7 × 117.2 |

---

## 2. 產生管線

```
Blender（headless）                    Godot（headless）
assets/blender/make_town.py    ──►  assets/models/*.glb ──┐
              make_props.py                                │
              make_trees.py（用 tree_lib.py）              │
              make_hedge.py                                │
              make_hieda.py ──► data/hieda_garden.*.json ──┤
                                data/town_modules.json ────┤
                                                            ▼
                                            tools/gen_town.gd
                                                            │
                             maps/village/village.tscn ◄────┤
                             maps/village/gen/*.res    ◄────┤
                             data/village.meta.json    ◄────┤
                             data/village.instances.json ◄──┘
```

**指令**（順序有意義）

```bash
# 0. 新烤的 glb 一定要先讓 Godot 匯入，否則 prop_mesh() 拿到空 mesh
godot --headless --path godot --import

# 1. 產圖
godot --headless --path godot --script tools/gen_town.gd

# 2. 靜態閘門
godot --headless --path godot --script tools/check_map.gd    # 全圖體檢
godot --headless --path godot --script tools/walk_test.gd    # 可走性 BFS
godot --headless --path godot --script tools/lm_ghost.gd     # 地標搬遷三項
godot --headless --path godot --script tools/portal_test.gd  # 傳送點串接
godot --headless --path godot --script tools/hieda_boundary_check.gd  # 稗田邸邊界安置

# 3. 視覺閘門（唯一抓得到「看起來不對」的）
#    ⚠ 旗標一定要在 -- 之後；⚠ shotdir 必須先存在（工具不會自己 mkdir）
mkdir -p /tmp/shots
xvfb-run -a godot --rendering-driver opengl3 --path godot -- \
  --map=village --shots=res://tools/shots/village_key.json --shotdir=/tmp/shots

# Blender：模式字先、路徑後（這個環境裡把 .png 當第一個參數會建出一個目錄）
blender -b -P assets/blender/make_town.py -- <outdir>
```

**檔案分工**

| 檔案 | 管什麼 |
|---|---|
| `tools/gen_town.gd` | 村圖的一切：地形／河道／路網／街區／地標內容／密度／街緣設施／水邊／草層 |
| `tools/gen_lib.gd` | 共用的幾何與材質工具（`box` `cyl` `gable_roof` `tuft_mesh` `blob_mesh` `terrain` `river_water` `pond_water` `make_multimesh` `pbr` `flat_mat`…） |
| `tools/gen_hieda.gd` | 稗田邸**獨立地圖**用的植栽發射器。**目前沒有人呼叫**，見 §7 |
| `tools/gen_village.gd` | 舊產生器。`_init()` 第一行就 `push_error` + `quit(1)`，**不可執行**。留著當 MIGRATE 的內容來源 |
| `assets/blender/tree_lib.py` | 唯一的樹產生器（第六輪把散落各處的版本合併掉的成果） |

---

## 3. 座標與空間約定

- **村座標**：`-z = 北`。原點在本通與廣場之間，廣場 `PLAZA = (0, 30)`。
- **glTF 匯出** `export_yup=True`；Godot 座標 = `(bx, bz, −by)`。
  再匯回 Blender 時是 Z-up 而且法線翻過。
- **河道** `RIVER_SPINE`（Catmull-Rom 樣條）是城鎮的結構脊椎，不是格線上的裝飾。
  `RIVER_HALF 7.0`、`RIVER_DEPTH 2.5`、水面半寬 `RIVER_HALF * 0.86 = 6.02`、
  水面高度 `bank_h − RIVER_DEPTH * 0.20`。
- **路網** `_roads`：本通（x=0，寬 8）、東西大街（z=30，寬 12）、四條橫街、
  五條縱街、兩條門引道。全部是折線，**不是格線**。
- **樹 glb 的材質槽順序 = 附加順序**：surface 0 = 樹皮、1 = 葉。
- **`town_modules.json`** 帶實測的 `fw/fd/h`、`gbox`（Godot 局部 XZ 包絡）、
  `facade` 錨點（`door_x` `door_w` `beam_z` `bay_w` `nbay`）。
  ⚠ 判互卡與跨水一律用 `gbox`，不要用 `fw/fd` 加假設。

---

## 4. 不可違反的規則

### 4.1 亂數分層
每一層有自己的 RNG，**不共用 `lib.rand`**。共用的話「加一叢草」會把全鎮町家重排。

| 層 | 種子 |
|---|---|
| 佈局／vista | `lib.rand`（`SEED`） |
| 密度層 | `SEED + 77` |
| 草層 | `SEED + 913` |
| 地標內容 | `SEED + 4177` |
| 街緣設施＋水邊 | `SEED + 5231` |
| 稗田邸院內植栽 | `SEED + 6011` |

搬新東西進來時的**自證方式**：搬完把受影響的子樹跟搬之前逐節點比對，
位移必須是 0。這一輪對六座地標做過兩次，都是 0。

### 4.2 碰撞
`own_colliders = true` → `main.gd` 只會替名為 `Terrain` 或帶 `needs_trimesh`
meta 的 `MeshInstance3D` 生 trimesh（`TRIMESH_MIN_SPAN = 15`）。
**`MultiMeshInstance3D` 不是 `MeshInstance3D`** —— 所以町家用逐棟旋轉的
`BoxShape3D`，不是 trimesh。碰撞形狀的 `owner` 一定要是 `_root`，
否則不會存進 `.tscn`（ADR-017）。

### 4.3 地標搬遷
`LANDMARKS` 有 `build` 鍵的地標**完全不走佔位分支** —— 不畫佔位方塊、
不掛佔位碰撞箱。「確保舊空殼碰撞箱被移除」最可靠的作法不是事後刪，
是**一開始就不要生**。保留區則**不論搬入與否都要登記**（那是町家與草
不准進來的唯一依據）。

### 4.4 保留區的數字從哪來
**實測幾何跨度**，不是零件擺放原點的散佈，也不是憑印象。
（足洗邸原點散佈 24.5m、真正的幾何跨度 32.9m —— 側牆自己長 16~18m。）
`lm_ghost` 每次都會把實測跨度印出來，直接抄那個數字。

### 4.5 驗證只信產出物
從 glb 頂點、`instances.json`、`.tscn` 的 buffer 量，**不要信產生器參數**。
產生器與檢查工具對不上時，先懷疑產生器的尺比較粗
（例：`_nearest_river_pt` 是點到**取樣點**、`poly_dist` 是點到**線段**，
前者永遠 ≥ 真實距離 → 產生器以為在岸上的蘆葦實測有 17/747 在水裡）。

### 4.6 引擎內截圖是最後一道閘門
Stage 4 的實例：石溝的溝蓋浮在石板路上 0.2m，**四道靜態閘門全部沒抓到**
（不是幾何錯誤、不影響可走性、不在保留區問題裡），本通街景截圖一眼就看到。
建 → 算圖 → 自我批判，再拿給人看。

---

## 5. 復發性病症目錄

查症狀，不要重推一次。

| 症狀 | 真因 | 修法 | 次數 |
|---|---|---|---|
| 一片面**全黑** | 兩片同法線的面共面（z-fighting + 法線退化）；`y=0` 牆面上的面尤其容易 | 錯開 ≥1cm，或改成不同方向的面。**不要有面剛好在 y=0 的牆平面上** | 6 |
| 整層**看不見**，但場景與體檢全綠 | 新烤的 glb 沒被 Godot 匯入 → `prop_mesh()` 拿到空 mesh | 先跑 `--import`；側面特徵是 `gen/mm_*.res` 只有 ~1KB。**現已由 `check_map._check_mm_alive` 自動抓** | 1 |
| 整層**看不見**，資料全對 | 對「鋪滿全圖」的 `MultiMeshInstance` 設了 `visibility_range` —— 它是拿**整批的 AABB 中心**算距離，不是逐實例 | 移掉。草層與密度層都中過 | 2 |
| 檢查對某類物件**結構性全盲** | 只掃 `MeshInstance3D`，漏掉 `MultiMeshInstance3D` | 逐實例解 MultiMesh buffer（`stride = 16 if use_colors else 12`，row-major 3×4）。⚠ **不能用 `get_instance_transform()`** —— headless 的 dummy 渲染器一律回單位矩陣 | 3 |
| 檢查拿**整棟的外框**比 | 群組的合併 AABB 就是「整塊地」，院子裡的東西全被誤判 | 逐片貼地構件（`_parts`）比 | 2 |
| 建物「浮空 / 半埋」 | 拿**中心點**的地面高度擺一個長物件 | `_ground_under()` 取 footprint 的**最低點**；⚠ 但這只治沉不治浮 —— **貼在地表上的東西（溝蓋）要錨自己中心** | 3 |
| 世界矩陣全是單位矩陣 | `SceneTree` script 裡節點不在樹上，`global_transform` 靜靜回傳單位矩陣 | 自己往上乘（`_world_xf` / `_wxf`） | 2 |
| 葉子／草是**白色碎片** | `tuft_mesh` 把顏色烤在頂點色，但 ArrayMesh 沒材質 → Godot 給預設白 | `tuft_mesh` 現在自己掛預設材質（呼叫端仍可覆蓋） | 1 |
| 尺寸「明明對」卻歪掉 | 旋轉沒算進去（鈴奈庵轉 −90°，W/D 對調）；或縮放沒除回去（神木母節點 ×3，碰撞形狀要除回去） | 一律用世界 AABB / OBB 量 | 2 |
| 葉片變成巨大碎片 | 葉尺寸用**絕對值**（配 8~11m 庭園樹的 0.50）套到 4.6m 的散佈樹上 | `tree_lib` 用 `leaf_h`（相對樹高） | 1 |
| Blender 參數中毒 | 這個環境裡把 `.png` 當 `--` 之後的第一個參數，會**建出一個目錄**、算圖存檔 EINVAL | 模式字先、路徑後 | 1 |

---

## 6. 驗證工具：驗什麼、驗不到什麼

### `tools/check_map.gd` —— 全圖體檢
驗：建物離地／建物互卡（2D OBB SAT，含旋轉）／散佈物長在建物裡／
水面在河床下／水面溢到平地／建物橫跨水面／**生物錯位**／**MultiMesh 是不是空的**。

- 町家是 `MM_machiya_*`，逐實例解 buffer 當**建物**（以前被當散佈物 → 169 棟對體檢隱形）。
- 散佈物比的是**逐片貼地構件**不是群組外框。
- 生物：鴨浮水面 ±0.35m、鯉在水下 0.05~1.2m、鷺鷥不能泡在水裡。
- **驗不到**：好不好看、比例對不對、材質對不對。

### `tools/walk_test.gd` —— 可走性
21 條路線的 BFS（village 9 / trail 1 / kourindou 2 / 稗田邸室內三層各 3）。`TRIMESH_MIN_SPAN = 15.0`。
**驗不到**：走起來舒不舒服、視線好不好。

### `tools/lm_ghost.gd` —— 地標搬遷三項
1. **結構**：佔位碰撞群組裡不該有已搬入地標的 shape
2. **物理**：在佔位方塊原本的位置放膠囊做 shape query，撞到的碰撞體必須有可見 mesh 祖先
3. **幾何**：真內容的世界 AABB 必須落在保留區內（含 MultiMesh，逐實例解 buffer）

每次都印實測跨度 —— 保留區要用那個數字填。

### `tools/portal_test.gd` —— 傳送點串接
每一跳驗四件事：雙向對接、落點物理（照 `main.gd` 的落點公式算 → 射線找地面
＋膠囊）、落點連通（BFS 到落點 30m 內的每個 portal）、地面判定用「高度帶內
取最高候選」。終點判定 = 走進 portal 的觸發圓柱（r1.6），不是站上中心格。
**驗不到**：傳送之後看到的畫面對不對。

### `tools/hieda_boundary_check.gd` —— 稗田邸邊界安置
從存好的 `village.tscn` **量成品**：footprint 跨度／外溢／保留區有沒有虛胖、
blockout 面數與 `needs_trimesh`／`CULL_DISABLED`、植栽 136 實例 10 模組、
離河距離、離三座地標塔的距離、緩衝疏林環帶寬度、外參道有沒有接上橫街、
室內 portal 在不在院子裡。
**驗不到**：材質好不好看、構圖對不對 —— 那還是只有截圖。

### `tools/hieda_site_scout.gd` / `tools/hieda_glb_probe.gd` —— 落點偵查
搬之前用的。scout 把 village.tscn 的內容打成 2m 佔用網格再掃淨空矩形
（順便回報離河／離塔／框內樹格）；probe 把 glb 拆開報 surface／面數／
材質／有沒有 UV。兩支都是**只量不動**。

### 登記表一致性（每輪自己跑一次即可）
`src/world/mapRegistry.js` ↔ `godot/data/<id>.meta.json`：`playSize` / `safe` /
`connections` / portal 目的地。外加 `godot/data/mapRegistry.json` 不能有孤兒
（`tools/export-godot.mjs` 現在是 merge + warn，不是直接覆蓋）。

### 「這個檢查還有沒有牙齒」
改鬆一個檢查之後，**故意注入一個該被抓到的錯**，確認它會叫。
（散佈物檢查改成逐片構件比之後，故意在主屋正中央種一株灌木 → 確實抓到，
而且訊息從「← 稗田邸」變精準成「← 稗田邸/主屋基壇」。）

---

## 7. 稗田邸：曾經是兩套，現在是一套

| | 現況（2026-08-07 起） |
|---|---|
| 在哪 | `village.tscn` 的地標之一，保留區中心 (−80.5, −195.8)、97.0 × 118.5 m |
| 是什麼 | `assets/models/hieda_blockout.glb`（22,600 面 / 1 draw call）＋ `data/hieda_garden.instances.json` 的 136 植栽實例（10 模組 → MultiMesh，`tools/gen_hieda.gd` 發） |
| 內容 | 主屋（唐破風玄関）＋格子塀＋棟門＋切石參道＋狛犬／石燈籠／框景巨樹＋水池＋涸れ滝＋枯山水＋菜園＋飛石＋木戶 |
| 室內 | 三層傳送場景（hieda1f / 2f / 3f），portal 在唐破風石階前 (−78.05, −164.6) |

**兩套合而為一**：村圖直接放完整版 blockout（使用者定案・完整版遷移改善書
v1）。原本那套程序化的「村內縮小版」（`_lm_hieda` 的築地塀→格子塀、
主屋、長廊／離れ、石組庭池、院內植栽 51 株）已整組刪除。

歷史上這裡踩過兩個坑，都記著：
1. Stage 0 的搬遷把 *舊 gen_village 的築地塀＋藥醫門* 當成定案前庭搬進村圖
   —— 兩套資產同名，肉眼分不出來。後來照 `make_hieda.py` 重建了一次前庭。
2. 那次重建（以及整個「村院另做小型植栽」的縮小版路線）之所以存在，唯一
   理由是**尺度**：當時的保留區只有 42.4×45.6，完整版要 95×117。改善書 v1
   推翻的正是那個前提 —— 保留區放大到 97×118.5，完整版就直接塞得進去了。

因此以下是**刻意保留的孤兒**，不要以為壞了就刪：
- `godot/assets/models/hieda_main.glb`（主屋單體；blockout 裡已經含一份）
- `godot/data/hieda_garden.markers.json` 裡 `target: null` 的木戶 portal

已**脫離**孤兒狀態（村圖在用）：`hieda_blockout.glb`、
`hieda_garden.instances.json`、`maps/hieda/gen/mm_hieda_*.res`（10 個）、
`tools/gen_hieda.gd`（`_lm_hieda` 直接呼叫它的 `emit()` —— 這支從第一天
就在等這個呼叫點）、`komainu_a.glb`、`stone_lantern.glb`（烘在 blockout 裡）。

---

## 8. 使用者裁決紀錄

| 決策 | 內容 |
|---|---|
| 天際線臨界 | 選 (c) |
| 河道與地標重疊 | 整合（水系優先，地標讓路） |
| 密度層時機 | 選 B：先在 sato 疊完地標高度與密度層，視覺定案後再一次性整合 |
| 整合方式 | 選 (a)：sato 產生器直接輸出到 `maps/village/`，MIGRATE 清單逐項搬入 |
| 自然池 | **不保留**，讓新河道取代 |
| 番屋／祭典幟旗 | **DEFERRED** |
| 雜物／小物密度 | 先不補，等 cel shading 視覺定案後再評估 |
| 稗田邸遷址 | 選 B：(−78, −164) |
| 稗田邸地形 | 方案 1：**地形整平**，不換位置、不加基壇（實測 0.98m → 0.00m） |
| 稗田邸舊址（z 向 110m 空地） | **留白**到材質階段再決定用途 |
| 地標搬遷順序 | 足洗邸 → 鈴奈庵 → 寺子屋 → 鎮守之杜 → 市場 → 稗田邸 |
| 稗田邸後院 | 村院**另做小型植栽**，後院全套留給獨立地圖 |
| 稗田邸前庭（修正版本混淆） | 村圖前庭換成 `make_hieda.py` 的定案版；先出「現況 vs 目標」節點差異清單再動手 |
| **稗田邸完整版遷移**（改善書 v1） | 放棄村內縮小版，完整獨立版（95×117）直接落地在人間之里北緣；保留區 45.2×48.2 → 97.0×118.5 |
| ├ 落點 | 原地擴張：blockout 原點 (−78, −178)，外參道端點正好接上 z=−135 橫街 |
| ├ 街網 | x=−104 / x=−52 兩條南北側街的北段（服務 0 棟町家）截到 z=−130 |
| ├ 河道 | 最近 100m，§2 的「無重疊」分支 —— 河維持原路徑，不動 |
| └ 緩衝疏林 | 邊界沒有林可清（是草地），改成在保留區外緣 3~9m 環帶**種** 46 株 |
| ├ C-1 庭池 | (a) **挪到主屋東側**，前庭淨空走完整定案構圖 |
| ├ C-2 主屋 | **程序化補唐破風玄関前廊**，不整棟換 `hieda_main.glb` |
| ├ C-3 植栽 | 前院撞位的挪開，村院總數維持 51 株 |
| └ C-4 圍牆 | 五段**全部**換格子塀，補完整圈（不做「格子塀硬接築地塀」） |
| 樹 | 合併成**單一**經過驗證的樹產生器（`tree_lib.py`）；花樹的無貼圖雙面頂點色材質路徑**不可再弄丟** |

---

## 9. 未結項目

### 9.1 貼圖／縮放／密度類 → 等 cel shading 階段一起處理
| 項目 | 現況 |
|---|---|
| 庭池石組讀成「平滑的灰麵包」 | 單顆玉石借 `stone_wall` 貼圖，縮到一顆填滿整張之後幾乎沒紋理 |
| 中島松（`tree_pine_a` × 0.72）近景偏稀疏 | 縮放問題 |
| **blockout 沒有貼圖** | 完整版是一份 join 過的烘焙網格，材質只有頂點色。遠景與鳥瞰很好看，但**近景**（站在參道上看牆、看瓦）是全平的色塊，旁邊的町家卻是有貼圖的 —— 全村唯一一棟沒貼圖的建築。要解得從 Blender 端**按材質族群拆 surface** 再讓 Godot 掛專案的材質庫，或做一支「頂點色 → 選貼圖組」的 shader。歸在這裡是因為 cel shading 那輪很可能把整個問題重新定義 |
| `make_hieda.py` 的 `TREE_H0 = 8.0` 對不上資產 | `hieda_pine_a.glb` 實測 6.92m，所以定案表寫的門前松 7.6/8.8m 實際長出來是 6.6/7.6m。村圖照抄**縮放係數**（跟獨立版同一棵樹），數字本身的帳留給獨立地圖那輪 |

### 9.2 水面／濕灘空隙 → **獨立記錄**，cel shading 開始前要先評估要不要做
**實測**：水面網格半寬 **6.02m**，但地形要到離河心 **~9.6m** 才露出水面 ——
中間 ~3.5m 是「低於水面但沒有水」的濕灘。
- 村心那段被砌石護岸擋住看不到（護岸範圍 = 離廣場 132m 內）
- 村外那段坡很緩，目前讀成濕沙灘，截圖裡不算難看
- **修正範圍**：要動 `RIVER_HALF * 0.86`，會連帶影響**護岸**（擺在 7.25m）、
  **橋**（跨距與橋台）、**鵜呑亭川床**（懸在水上 3.5m 是照現在的水面算的）、
  以及 `check_map` 的水面檢查門檻
- 所以這**不是材質問題**，不能跟 §9.1 一起延後 —— cel shading 動工前要先決定

### 9.3 睡蓮形狀 → **獨立記錄**，cel shading 修不好它
睡蓮用 `lib.tuft_mesh` 做，出來是**放射狀的葉叢**（葉片往外又往上，約 45°），
不是平貼水面的浮葉。這是**幾何**問題不是材質問題：換貼圖／換色調都不會讓它
變成浮葉。要改的是模組本身（例如把 `base_h` 壓到 `spread` 的 1/5 讓葉片近乎平躺，
或另做一個真正的浮葉模組）。影響兩處：村圖河道的 `WaterPlants/睡蓮`（220 株）、
稗田邸庭池的 `睡蓮_*`（11 株）。

### 9.4 其他
- **農田系統**：獨立階段，未開工（草層那輪明確標「稻田不搬」）
- **番屋／祭典幟旗**：使用者裁決 DEFERRED
- **稗田邸獨立地圖**：完整版已經落在 village 裡了，「另開一張圖」這件事本身
  變成待裁決 —— 要嘛取消（村圖已經有完整的它），要嘛那張圖改放別的內容。
  `hieda_garden.markers.json` 裡那個 `target: null` 的木戶 portal 也跟著待定
- **清理候選**：`godot/maps/village/mm_hedge_{a,b,c}.tres`（約 2MB）是舊 `gen_village`
  留下的孤兒，全庫沒有任何引用（只剩編輯器的 filesystem cache）。沒有刪，等指示

---

## 10. 明確排除（本階段不做）

- 🚫 戰鬥／衝刺用的碰撞牆準備
- 🚫 人群／NPC 模擬（等 NPC 系統存在）
- 🚫 材質／光照／cel-shading pass（整合輪明確排除，成果留在 §9.1）
