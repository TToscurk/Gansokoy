# 博麗神社 v3（全面重製候選）

狀態：**ART_REVIEW**（未批准、未切換正式）。舊神社 `maps/shrine/` 與候選 v2 `maps/shrine_v2/` 一個位元組都沒動。

```bash
godot --path godot -- --map=shrine_v3      # 直接開候選圖（出生在南端獸道口 −17.3, 5.0, 90.7，面向石段腳）
```

施工前的空間判讀：[`00_空間判讀.md`](00_空間判讀.md)。第一輪總表圖（10:30 日光，14 個視角）：[`sheet_final.jpg`](sheet_final.jpg)。
第二輪美術深化：問題標記與策略 [`01_美術深化_問題與策略.md`](01_美術深化_問題與策略.md)；修正前／後同角度對照 [`polish_compare_A.jpg`](polish_compare_A.jpg)（石段、鳥居、前庭）、[`polish_compare_B.jpg`](polish_compare_B.jpg)（參道、手水舍、拜殿、倉庫、俯瞰）。
第三輪植被光照一致性（2026-10-23）：原因、逐項排查、逐步修正的數字與回退 [`02_植被光照診斷.md`](02_植被光照診斷.md)；對照 [`light_compare_A.jpg`](light_compare_A.jpg)、[`light_compare_B.jpg`](light_compare_B.jpg)、同一棵櫻四面 [`light_same_tree.jpg`](light_same_tree.jpg)。葉卡改用 v3 自己的 `assets/shrine_v3/shaders/veg_leaf.gdshader`（陰影 pass 保留葉隙），本圖白天的天空補光在 `maps/shrine_v3/s3_light_profile.gd`。

## 第二輪：美術深化（2026-10-22，保留第一輪的地形、建築、動線）

地形高度沒動（`h_near.f32`／`h_mid.f32` 的 MD5 與修正前相同）；建築本體、鳥居、池塘、傳送點、劇情互動區、出生點都在原位。使用者同意「樹以外可用內部資產」，樹仍全是 v3 自製樹。

| 項目 | 改了什麼（公尺） |
|---|---|
| 石段兩側 | 新函式 `add_stair_sides()`：耳石外 1.8–2.5 m 一條斷續低植被（107 株）、27 個波浪邊斜橢圓植物團（內列 \|x\| 2.6–5.5 小團、外列 6–12 大團；西側團距短）、3 棵小樹（楓 2、山櫻 1，受視線走廊樹高上限）、團內岩石有一圈苔／蔭草。三層＝低（蔭草、矮草、苔、落葉、細枝）、中（蕨 4 種、熊笹、蕗、灌叢）、高（既有林＋新小樹）。 |
| 石燈籠（4 → 5 座） | 鳥居左側單座（大 ×1.15，(−3.5, 8.6)）→ 參道中段一對（小，(±2.6, −5.0)）→ 拜殿前一對（大 ×1.1，(±3.7, −12.6)，在漸寬段起點）→ 狛犬 (±2.25, −15.6) → 賽錢箱 (0, −17.2)。拜殿前燈籠第一次放在 z −16.6 時從斜角和狛犬疊在一起，前移到 −12.6 拉開 3 m 縱深。 |
| 參道（`make_site.py` 重寫） | 三段鋪法：鳥居端自然不規則石（Voronoi，寬 2.3–2.6 m，旋轉 3–8°）→ 中段切石成排錯縫（主石帶 2.4 m＋兩側碎石／輔石）→ 漸寬成 6.6 m 的拜殿前台（較規整）。467 塊、109 m²；下沉 25、濕暗 22、缺角 17、破石 25、邊緣碎石 68、輔石 13。每塊石頭頂面只高出地面最高點 1.4 cm（第一次 3 cm 讀成「擺在地上」）、主石倒角 0.8–0.9 cm、縫：切石 1.6–3.6 cm、自然石 2.4–5.2 cm；下沉的石頭只比鄰石低 0.6–1 cm（沉 1.2–2 cm 會被地形蓋住、讀成缺一塊）；每塊的色調與苔量在頂點色（`s3_paving` 材質、`s3_stone.gdshader` 的 `vc_moss`）。手水舍加不規則切石台 3.4×3.8 m。 |
| 地表（遮罩＋地形 shader） | 新 `mask_c`：R＝踩踏量（參道兩側、拜殿前、往手水舍／倉庫）、G＝楓落葉、B＝鋪石接地陰影、A＝前庭 6–12 m 尺度土色分區。夯土壓暗 12%、踩踏處壓實（略灰略暗，不再提亮）、暖赭↔冷褐分區、鋪石縫與石外 0.3 m 稍暗、參道邊斷續的花瓣帶、楓樹下落葉斑。前庭草叢依踩踏量減少（6,793 → 5,626）、邊緣改成零星雜草／苔斑（160 株）。 |
| 鳥居／手水舍／倉庫 | 鳥居兩側：燈籠旁苔岩＋灌木＋蕨、右側小楓（定點樹，非對稱）、柱腳苔。手水舍：石台、背側蕨與草本、台邊短草。倉庫：牆腳（滴水線外）草、背側到林緣的蕨／熊笹／灌叢過渡、南牆東段柴堆＋木盆（內部資產，盒碰撞）。拜殿兩側與背後、西柵內側、平台南緣各加幾團低植被（西柵內只放 < 0.8 m 的，不擋外望）。 |
| 陰陽玉彩蛋 | `D:\資產glb\博麗神社\陰陽玉.glb`＝專案內 `assets/shrine/陰陽玉.glb`（MD5 `1fa479cd4da76d2a1132486c7ced17a9` 相同）。轉成 `models/onmyoudama.glb`：直徑 0.26 m、94,844 → 3,999 三角形、貼圖 4096 → 512；原檔粗糙度貼圖平均約 0.01（塑膠亮面）→ 粗糙度 0.66、金屬 0（規格 §27）。位置 (16.38, −19.78)：倉庫北牆外、木箱東側，兩顆苔石之間、半埋在楓落葉裡（規格 §26 LEVEL 3：全圖 1 顆、不放參道）。走到旁邊出現「[E] 調查」→ 緣一 3 句獨白（新檔 `data/dialogue/yoriichi_onmyoudama.json`）→ 立 `found_onmyoudama`，不動任務。 |
| 內部資產（樹以外） | 獸道 S01 套件地被 24 種（`assets/beast_path/s01_kit/glb/`，只讀）→ `tools/shrine_v3/build_internal.gd` 轉成 `assets/shrine_v3/mesh/int/`（含 LOD1，材質沿用 `tools/beast_path/s01_dress.gd` 的 `veg_mat`＝`meadow_grass.gdshader`，風力系統自動接成 grass）；`assets/village_v2/humanuse_kit/mesh/` 的柴堆、木盆直接引用。執行期 MultiMesh 共 1,440 株、23 個圖層（`s3_scatter.gd` 新增 stride 7：貼坡、實例色、LOD1）。 |
| 工具 | `build_scene.gd` 每一段用自己的隨機種子（改一區不洗掉其他區）；`s3lib.save_retry()`：Windows 上偶發「Cannot save file」（同一管線兩次各有一個檔第一次存不進去）→ 存檔一律重試。 |

### 第二輪驗證（最終場景）

| 項目 | 結果 |
|---|---|
| 實走（`walk_shrine_v3.gd`） | **10 段全到達**（新增 4b 倉庫→陰陽玉、4c 回倉庫前），實走 333.7 m，穿地 0／268，鏡頭在碰撞體內 0／268（無頭）。第 5 段（倉庫→櫻林）的測試路線原本是直線 (6, −12)→(−5.6, −12.6)，正好穿過新的左燈籠位置，第一次實走卡在燈籠；路線改成從燈籠前 1.1 m 走過 (z −11)，燈籠位置不變。 |
| 實錄影片（`--record`，Movie Maker 60 fps＝原速） | `_review/shrine_v3/video/shrine_v3_polish_walk_60s.mp4`（不入版控，59.5 s，1152×648）：獸道口→石段→鳥居→前庭→拜殿前→倉庫側→陰陽玉→倉庫前→櫻林→池塘北岸，8 段全到達。有渲染的這次鏡頭在碰撞體內 **0／573**（第一輪 4／535）、穿地 0／573。抽格看：櫻林段有一棵樹幹短暫擋在鏡頭與角色之間（鏡頭不在碰撞體內）。 |
| 互動區 | 陰陽玉旁站位在「陰陽玉」互動區內；石段腳、拜殿前兩個舊互動區照舊。 |
| 導航網格 | 7 段全通（新增 倉庫前→陰陽玉旁 6.7 m），終點誤差 ≤ 0.50 m。 |
| 劇情（`verify_story_v3.gd`） | **34／34 PASS**：原 29 項＋新增 S13 五項（「調查」提示、第一句、3 步推進到結束、`found_onmyoudama`、MQ07 進度不變）。 |
| 接地量測（腳印 9 點） | 燈籠 5 座底面全部低於腳印地面 6.8–28 cm（鳥居左那座腳印內坡差 19 cm：29.81–30.00 m，原本低側懸空 9.4 cm，改成落在腳印最低點）；賽錢箱底面高出地面 1.2–2.8 cm＝坐在前台石頂上（原本 3.0–4.6 cm）；陰陽玉埋入 3.4–3.8 cm；柴堆、木盆埋入 1.8–2.4 cm。 |
| 風力接線（`Wind.veg_stats()`） | grass 236 → 670、bush 291 → 300、broad_tall 292 → 303、broad_small 28 → 30、conifer 153，未知物種 0。 |
| 腳本檢查 | 這輪改到的 `.gd`（build_scene、build_internal、build_assets、build_terrain、s3lib、s3mat、s3_scatter、walk、verify_story）全 PASS。 |
| 效能（GTX 1070、1600×900；括號內＝第一輪） | 前庭 60（60）、南外望 60、石段腳 60（60）、獸道口 52（50）、櫻林 59（54）、鳥瞰 61（57）FPS；三角形 4.39–6.38 M（4.4–6.2 M）；**draw calls 499–958（376–598），多了約 60%**——23 個地被圖層 × 20 m 分塊。 |

## 做了什麼（第一輪）

從空地重建，沒有沿用任何舊神社的地形、模型、材質或貼圖。

| 項目 | 內容（公尺） |
|---|---|
| 地形 | 三層：近景 156×204 m（0.75 m 格，含碰撞）、中景 2.4 km（6 m 格）、遠景 18 km（60 m 格），同一個 `regional()` 高度函數，接縫處高度與法線都對齊。平台 y＝30.0，不規則多邊形約 50×43 m，位在山體西南肩。 |
| 開口方向 | 南（正面）與西（左手）。從前庭四個站位量 150 m 內地形最大仰角：南～西扇區 −2.98° ～ −5.13°（全部低於水平）。北、東北、東三面才上升。 |
| 西崖 | 柵外崖高沿崖線 6–12 m 變化（不是一道等高的牆），崖下接約 32° 林坡；坡上 16 塊岩露頭、樹與灌木。 |
| 石段 | 90 階、5 段（各 18 階）、每階高 0.167 m、踏面 0.34 m、寬 2.8 m、4 個 2.4 m 平台；z 9.6 → 48.1，y 30.0 → 15.0。每階兩塊切石＋兩側耳石；碰撞為每段一個坡道盒＋平台盒。 |
| 拜殿（唯一主殿） | (0, −23)，朝南。主體 6.0×4.2 m，含向拜與前階外包 8.44×6.10×8.53 m。木造、略舊；注連繩、紙垂、鈴緒、賽錢箱。靈夢起居整合在拜殿內，不另做住居與本殿。 |
| 鳥居 | 明神鳥居，(0, 7.4) 階頂；笠木 5.64 m、高 4.74 m；二段石台、注連繩三房二紙垂、「博麗神社」額。 |
| 倉庫 | (15.2, −17.4)，朝西；3.9×3.58×3.59 m（遠小於拜殿）；旁邊放木箱 3、竹箒 1。 |
| 手水舍 | (−8.6, 0.6)，朝東；3.0×3.14×2.63 m；水盤有水面；旁邊放木桶。 |
| 石燈籠／狛犬／社號標 | 燈籠 4（鳥居內 1.81 m ×2、拜殿前 2.26 m ×2）；狛犬阿吽一對（台座 0.94 m＋像 0.77／0.86 m）；石段腳社號標 2.12 m。 |
| 前庭地面 | 泥地與草地交錯，中軸踩踏帶與建築周圍才是連續夯土；石板參道寬 1.3 m（鳥居→拜殿），外加往倉庫、手水舍的飛石；北半部少量苔痕。 |
| 池塘 | 拜殿右後方、比前庭高 2.5 m 的棚地上；中心 (17.5, −42.5)，水面約 14×9 m，水面 y 32.15，最深 1.15 m；自然岸線＋岸石；水線內有隱形矮牆，玩家站得到水邊、走不進池裡。瀑布與木棧台依規格刪減。 |
| 植被 | 樹 473 棵（山櫻 98、楓 28、櫟 140、櫸 54、杉 152、赤松 1），灌木 170（其中 80 叢在南坡／西崖下的視線走廊，樹冠頂低於平台面），草叢 6,793、蕨 520（執行期分塊 MultiMesh）。視線走廊內的樹，樹冠頂一律低於前庭眼高。 |
| 系統接線 | `data/shrine_v3.meta.json`（新檔）：通往獸道的傳送點 (−18, 94.6)；互動區「參道抵達」(REACH `hakurei_shrine_approach`) 與「拜殿拜訪」(互動 `hakurei_shrine_visit`、對話 `reimu_hakurei_shrine`、require_quest MQ04)；NavigationRegion3D（3,979 多邊形）；風力系統依檔名前綴自動接線（樹、草）。 |

## 驗證結果（2026-10-22，最終版場景）

| 項目 | 結果 |
|---|---|
| 實走（`walk_shrine_v3.gd`，真 main.tscn、真玩家、真輸入） | **8 段全到達**：獸道口→石段腳 53 m（y 4.7→14.9）→石段→鳥居 48 m（14.9→30.0）→前庭→拜殿前 20 m→倉庫側 14 m→櫻林邊緣 49 m→池塘北岸 35 m→池塘西岸 13 m→回程下石段 84 m。穿地 0／255 次取樣，鏡頭在碰撞體內 0／255。 |
| 互動區 | 石段腳在「參道抵達」區內；拜殿前在「拜殿拜訪」區內。 |
| 導航網格連續 | 6 段全通（獸道口→石段腳→鳥居內→拜殿前→倉庫前→櫻林→池畔），終點誤差 ≤ 0.50 m。 |
| 劇情（`verify_story_v3.gd`，MQ04 靈夢初見全流程） | **29／29 PASS**：指路、REACH、「[E] 拜訪」提示進出、對話鎖定、靈夢第一句、25 步對話、met_reimu、MQ04 完成→MQ07、repeat 對話、重複進出不動任務、換圖到獸道再回來站在地面。 |
| 腳本檢查（`tools/dev/gd_check.py`） | 本次 10 個 .gd 全 PASS。全專案模式 461 檔有 1 個 FAIL：`tools/p11r2/_patched/yoriichi_character.gd`，不是這次的檔案，沒動。 |
| 風力接線（`Wind.veg_stats()`） | broad_tall 292、broad_small 28、conifer 153、bush 291、grass 236 個實例／分塊，未知物種 0。 |
| 效能（GTX 1070、1600×900） | 前庭／石段 60 FPS（垂直同步上限），櫻林 54 FPS、獸道口 50 FPS（20.2 ms）、鳥瞰 57 FPS；每幀 4.4–6.2 M 三角形（含陰影）、376–598 draw calls。 |
| 實錄影片（`--record`，Movie Maker 60 fps＝原速） | `_review/shrine_v3/video/shrine_v3_walk_56s.mp4`（不入版控，55.7 s，1152×648）：獸道口→石段→鳥居→前庭→拜殿前→倉庫側→櫻林→池塘北岸，6 段全到達。有渲染的這次鏡頭在碰撞體內 4／535 次取樣（倉庫側 1、櫻林 1、池北 2）；無頭實走為 0。 |

## 檔案

第一輪全部是新檔。第二輪在 v3 自己的資料夾外只多一個新檔 `godot/data/dialogue/yoriichi_onmyoudama.json`；內部資產（`assets/beast_path/s01_kit/glb/`、`assets/village_v2/humanuse_kit/mesh/`、`assets/village_v2/meadow/meadow_grass.gdshader`、`tools/beast_path/s01_dress.gd`、`assets/shrine/陰陽玉*`）只讀取／引用，沒有修改：

- `godot/maps/shrine_v3/`：`shrine_v3.tscn`（候選場景）、`s3_scatter.gd`（執行期草／蕨／地被）、`gen/`（地形網格、碰撞、遮罩 a／b／c、導航、`layout.json` 等）
- `godot/assets/shrine_v3/`：`src/`（Blender 原始碼＋`shrine_v3_arch.blend`、`shrine_v3_site.blend`、`make_onmyoudama.py`；`.gdignore`）、`models/`（GLB＋碰撞 JSON）、`mesh/`（`mesh/int/`＝內部地被轉檔）、`scenes/`、`mat/`、`shaders/`（6 個）、`tex/ph/`（Poly Haven CC0，來源與 MD5 在 `SOURCES.json`）、`tex/gen/`（自製扁額、刻字、鈴緒；陰陽玉 512 貼圖）、`tex/veg/`（自製葉卡 8 種）
- `godot/tools/shrine_v3/`：生成、建構、截圖、實走、劇情驗收工具（第二輪新增 `build_internal.gd`、`shots_polish.json`、`compare_sheet.py`）
- `godot/data/shrine_v3.meta.json`、`godot/data/dialogue/yoriichi_onmyoudama.json`
- `docs/shrine_v3/`：本檔、空間判讀、美術深化策略、總表圖、修正前後對照

## 重建流程

```bash
cd godot
python tools/shrine_v3/gen_terrain.py                                     # 高度、配置、遮罩
godot --headless --path . --script res://tools/shrine_v3/build_terrain.gd
BL=/d/Blender/blender-5.2.1-windows-x64/blender.exe
$BL -b --factory-startup --python assets/shrine_v3/src/make_arch.py       # 建築、道具
$BL -b --factory-startup --python assets/shrine_v3/src/make_site.py       # 石段、參道、木柵、岩石（讀地形高度）
$BL -b --factory-startup --python assets/shrine_v3/src/make_veg.py        # 樹、灌木、蕨
godot --headless --path . --import && python tools/shrine_v3/fix_texture_imports.py && godot --headless --path . --import
godot --headless --path . --script res://tools/shrine_v3/build_assets.gd
godot --headless --path . --script res://tools/shrine_v3/build_veg.gd
$BL -b --factory-startup --python assets/shrine_v3/src/make_onmyoudama.py  # 陰陽玉（讀 assets/shrine/陰陽玉.glb）
godot --headless --path . --script res://tools/shrine_v3/build_internal.gd # 內部地被（讀 assets/beast_path/s01_kit/glb/）
godot --headless --path . --script res://tools/shrine_v3/build_scene.gd   # 也寫 data/shrine_v3.meta.json
# 驗證
godot --headless --path . --script res://tools/shrine_v3/walk_shrine_v3.gd -- --map=shrine_v3
godot --headless --path . --script res://tools/shrine_v3/verify_story_v3.gd -- --map=shrine_v3
godot --path . --resolution 1600x900 --script res://tools/shrine_v3/shots.gd -- --shots=res://tools/shrine_v3/shots_final.json --out=<資料夾> --hour=10.5
godot --path . --resolution 1600x900 --script res://tools/shrine_v3/shots.gd -- --shots=res://tools/shrine_v3/shots_polish.json --out=<資料夾> --hour=10.5 --frames=40
python tools/shrine_v3/compare_sheet.py <修正前資料夾> <修正後資料夾> <輸出前綴>   # 前後對照表
```

`gen/*.bin`、`gen/*.rgba` 是 `gen_terrain.py` 的中間檔（不進版控），`build_terrain.gd` 需要它們。

## 未解問題（非阻斷，等使用者審）

第二輪美術深化後仍在的（最終審圖的結論；沒有阻斷性問題：無浮空、無穿模、主路與拜殿入口無遮擋）：

1. 鳥居端的自然石在低角度陽光下，石緣仍有一圈深色邊帶（倒角＋露出的側面），近看「坐進土裡」約 6／10；石塊偏大、多邊形感重。中段與拜殿前台較好。
2. 前庭與倉庫周圍的夯土在俯瞰時仍偏淺、偏同一色、面積大；已加 6–12 m 土色分區與接地陰影，但大尺度差異還不夠。
3. 手水舍的切石台外形太方，像貼在地上。
4. 紅楓（石段中上段與鳥居一帶）飽和度偏高，搶過櫻與鳥居。
5. 鳥居正面視角裡，鳥居左側那座大燈籠和鳥居互相搶。
6. 石段兩側：林冠已成林，但坡面的團與團之間仍有成片空地（有意留空），蕨在下坡看時仍看得出一株一株。
7. Draw calls 比第一輪多約 60%（499–958）；GTX 1070 上 FPS 沒掉，但較弱的顯卡要再合併地被圖層。

第一輪留下、這輪沒動的：

8. 西坡：崖已降成 6–12 m 並長了樹，但從遠處西側看，樹叢之間仍有成片裸露岩面。根因是外圍山體西翼本身平均約 46°（x −24 → −78 連續落 57 m）；要再緩就得改 `regional()` 的西谷形狀，中景與遠景會一起變。
9. 中遠景山體的林冠材質在鳥瞰距離看得出重複圖樣。
10. 池塘水面材質斑紋偏粗。
11. 石段石材紋理逐階重複；鳥居漆面比周圍乾淨。
12. 樹沒有 LOD（每棵 3–7 k 三角形、可見距離 600 m）：獸道口 52 FPS。要再省就做遠景樹的公告板替身。
13. 平台邊緣規劃的低矮野面石垣沒做：南緣改用散置岩塊與灌木收邊，西緣用木柵。

## 切換正式與回退

- **回退**：第二輪的修改都在 v3 自己的資料夾＋一個新對話檔；`git revert` 第二輪的提交即回到第一輪交付版。整個不採用的話，刪掉 `godot/maps/shrine_v3/`、`godot/assets/shrine_v3/`、`godot/tools/shrine_v3/`、`godot/data/shrine_v3.meta.json`、`godot/data/dialogue/yoriichi_onmyoudama.json` 就回到原狀。
- **切換正式**（需使用者先給 `ART_APPROVED`）：建議「同 id 換內容」——舊 `maps/shrine/` 改名保留，候選場景與 meta（id 改 `shrine`）放進原路徑，回退＝改名換回。仍引用 `"shrine"` 的地方（2026-10-22 搜尋）：`data/waypoints.json`（3 個目標＋邊界表）、`data/trail.meta.json`、`maps/trail/trail.tscn` 傳送區 metadata、`data/mapRegistry.json`、`data/combat_spaces.json`、`data/shrine.meta.json`、`scripts/main.gd:321`、`scripts/ambience.gd:32`、`scripts/dev/review_start.gd:24`。另外，`waypoints.json` 的「拜殿」目標 (0, −21) 在 v3 落在拜殿建物內，切換時要改成 (0, −15.5)；石段的 (0, 40) 在 v3 可直接沿用。
