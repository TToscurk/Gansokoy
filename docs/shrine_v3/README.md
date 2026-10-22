# 博麗神社 v3（全面重製候選）

狀態：**ART_REVIEW**（未批准、未切換正式）。舊神社 `maps/shrine/` 與候選 v2 `maps/shrine_v2/` 一個位元組都沒動。

```bash
godot --path godot -- --map=shrine_v3      # 直接開候選圖（出生在南端獸道口 −17.3, 5.0, 90.7，面向石段腳）
```

施工前的空間判讀：[`00_空間判讀.md`](00_空間判讀.md)。總表圖（10:30 日光，14 個視角）：[`sheet_final.jpg`](sheet_final.jpg)。

## 做了什麼

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

## 檔案

全部是新檔，沒有修改任何既有檔：

- `godot/maps/shrine_v3/`：`shrine_v3.tscn`（候選場景）、`s3_scatter.gd`（執行期草／蕨）、`gen/`（地形網格、碰撞、遮罩、導航、`layout.json` 等）
- `godot/assets/shrine_v3/`：`src/`（Blender 原始碼＋`shrine_v3_arch.blend`、`shrine_v3_site.blend`；`.gdignore`）、`models/`（GLB＋碰撞 JSON）、`mesh/`、`scenes/`、`mat/`、`shaders/`（6 個）、`tex/ph/`（Poly Haven CC0，來源與 MD5 在 `SOURCES.json`）、`tex/gen/`（自製扁額、刻字、鈴緒）、`tex/veg/`（自製葉卡 8 種）
- `godot/tools/shrine_v3/`：生成、建構、截圖、實走、劇情驗收工具
- `godot/data/shrine_v3.meta.json`
- `docs/shrine_v3/`：本檔、空間判讀、總表圖

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
godot --headless --path . --script res://tools/shrine_v3/build_scene.gd   # 也寫 data/shrine_v3.meta.json
# 驗證
godot --headless --path . --script res://tools/shrine_v3/walk_shrine_v3.gd -- --map=shrine_v3
godot --headless --path . --script res://tools/shrine_v3/verify_story_v3.gd -- --map=shrine_v3
godot --path . --resolution 1600x900 --script res://tools/shrine_v3/shots.gd -- --shots=res://tools/shrine_v3/shots_final.json --out=<資料夾> --hour=10.5
```

`gen/*.bin`、`gen/*.rgba` 是 `gen_terrain.py` 的中間檔（不進版控），`build_terrain.gd` 需要它們。

## 未解問題（非阻斷，等使用者審）

1. 西坡：崖已降成 6–12 m 並長了樹，但從遠處西側看，樹叢之間仍有成片裸露岩面。根因是外圍山體西翼本身平均約 46°（x −24 → −78 連續落 57 m）；要再緩就得改 `regional()` 的西谷形狀，中景與遠景會一起變。
2. 中遠景山體的林冠材質在鳥瞰距離看得出重複圖樣。
3. 草叢仍看得出「一叢一叢」的分布，不是連續草地。
4. 池塘水面材質斑紋偏粗。
5. 石段石材紋理逐階重複；鳥居漆面比周圍乾淨。
6. 樹沒有 LOD（每棵 3–7 k 三角形、可見距離 600 m）：獸道口 50 FPS。要再省就做遠景樹的公告板替身。
7. 平台邊緣規劃的低矮野面石垣沒做：南緣改用散置岩塊與灌木收邊，西緣用木柵。

## 切換正式與回退

- **回退**：這次沒有改任何既有檔。不採用的話，刪掉 `godot/maps/shrine_v3/`、`godot/assets/shrine_v3/`、`godot/tools/shrine_v3/`、`godot/data/shrine_v3.meta.json` 就回到原狀。
- **切換正式**（需使用者先給 `ART_APPROVED`）：建議「同 id 換內容」——舊 `maps/shrine/` 改名保留，候選場景與 meta（id 改 `shrine`）放進原路徑，回退＝改名換回。仍引用 `"shrine"` 的地方（2026-10-22 搜尋）：`data/waypoints.json`（3 個目標＋邊界表）、`data/trail.meta.json`、`maps/trail/trail.tscn` 傳送區 metadata、`data/mapRegistry.json`、`data/combat_spaces.json`、`data/shrine.meta.json`、`scripts/main.gd:321`、`scripts/ambience.gd:32`、`scripts/dev/review_start.gd:24`。另外，`waypoints.json` 的「拜殿」目標 (0, −21) 在 v3 落在拜殿建物內，切換時要改成 (0, −15.5)；石段的 (0, 40) 在 v3 可直接沿用。
