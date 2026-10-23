# 獸道 S04 方案 A（崖頂上游溪水材質）— 測試紀錄與正式撤回

- **最終狀態（2026-10-15 使用者裁定）：方案 A 已測試、玩家視角不可見、正式撤回。S04 以 V1.3 為美術基準；現行工作區與 V1.3 備份逐檔相同（341／341）。S04 的地形、天然地表、岩壁、森林與瀑布美術工作至此停止。**
- 整體關卡仍是 **ART_REVIEW**（未 ART_APPROVED），等戰鬥攝影機與實際 BOSS 戰可玩性驗收；未 commit。
- 備份（獸道目錄不在 git 裡，這兩份是唯一備份，各附 sha256 清單，皆保留、核對 OK）：
  - **V1.3**：`C:/Users/B365/AppData/Local/hermes/backups/beast_path_v13_20261015/`（341 檔）＝現行工作區
  - **V1.3.1（方案 A 套用版）**：`C:/Users/B365/AppData/Local/hermes/backups/beast_path_v13_1_water_20261015/`（342 檔）
- 本文 §1 是撤回作業，§2 起是方案 A 當時的測試紀錄（保留作證據，數字都是 V1.3.1 當時量到的）。
- 相關獨立紀錄：[`TECH_ISSUE_generate_only_flag_leak.md`](TECH_ISSUE_generate_only_flag_leak.md)（生成日誌 9 行資源洩漏警告的定位）。

## 0. 結論

1. **方案 A 做了一次、效果有限、且玩家看不到。** 自由鏡頭下崖頂溪水「讀得出是水」，但白紋規整、崖口硬接縫沒變；玩家 25 個第三人稱鏡位（含 6 個最大仰角仰望崖頂）把崖頂溪水面塗洋紅色再數像素，最多 **11 px／1,440,000 px**（0.0008 %）。
2. **使用者裁定正式撤回**：問題只存在於自由攝影機，不值得多一份材質與維護成本。已撤回，S04 回到 V1.3。
3. **我的順序錯了（記錄）**：裁定是「玩家看不到就停」，我先做了修改、才做可見度檢查；修改因此在場景裡留到本次收尾才撤回。

## 1. 撤回作業（2026-10-15 收尾）

### 1.1 先比對：V1.3 → V1.3.1 的本輪專屬範圍

動手前先確認三件事：①工作區當時與 V1.3.1 快照**逐位元相同**（342 檔、差異 0）＝這段時間沒有別的 session 動過獸道目錄；②V1.3 → V1.3.1 只有 9 個修改＋1 個新增；③本輪的識別字（`bp_water_stream_head`、`alpha_floor`、`flow_streak`、`STREAM_HEAD_MAT_PATH`、`head_mat`、`mark=head`、`WaterBuf`、`water.head_material`）在 `godot/`（不含 `.godot` 快取）只出現在這 10 個檔中的 9 個（`beast_path.tscn` 只差 `unique_id`），其他檔 0 次。

| 檔 | 本輪改動（逐行見 `evidence/v13_to_v13_1.patch`） | 撤回方式 |
|---|---|---|
| `assets/beast_path/materials/bp_water.gdshader` | +10／−1：2 個 uniform、`alpha` 下限改讀 `alpha_floor`、順流水紋區塊 | 從 V1.3 備份還原 |
| `…/bp_water_pool.tres`、`…/bp_water_stream.tres` | 各 +2：`alpha_floor = null`、`flow_streak = null`（生成器重存時多出，語意＝預設值） | 從 V1.3 備份還原 |
| `…/bp_water_stream_head.tres`（新） | 新增 22 行（887 B） | **刪除**（見 1.2） |
| `tools/beast_path/terrain_generator.gd` | +43／−13：`WaterBuf`、`build_water(…, head_mat)`（第二 surface）、`STREAM_HEAD_MAT_PATH`、寫專用材質 | 還原 |
| `tools/beast_path/generate_beast_path.gd` | +1／−1：呼叫 `build_water` 時帶入專用材質 | 還原 |
| `tools/beast_path/verify_beast_path.gd` | +115：`water.head_material` gate、`_head_water_check`、`_shader_default`、`TerrainGen` preload | 還原（gate 撤回，見 1.3） |
| `tools/beast_path/diag_shots.gd` | +22：`mark=head` 實驗、6 個仰望鏡位 p01～p06 | 還原（`mark=head` 依賴已撤回的第二 surface；V1.3.1 版留在 patch／備份） |
| `maps/beast_path/s04_boss_clearing.tscn` | Water 網格 1 個 surface（492 點）→ 2 個（420＋72 點） | 從 V1.3 備份**逐位元**還原 |
| `maps/beast_path/beast_path.tscn` | 只差 `unique_id` | 同上 |

文字檔差異存成 `evidence/v13_to_v13_1.patch`（8 個檔，217 行新增／15 行刪除）。**已在暫存目錄驗證：把它 `patch -p1` 套在 V1.3 備份上，8 個檔的結果與 V1.3.1 備份逐位元相同。**要重啟方案 A：在 `D:/神社/shrine` 下 `patch -p1 < docs/art_review/beast_path_v13_s04_water/evidence/v13_to_v13_1.patch`，再跑 `generate_beast_path.gd -- --only=S04`（重生這一步在本次收尾沒有重做）。

### 1.2 怎麼撤回（逐檔，沒有整包覆蓋）

1. 前置檢查：要動的 8 個檔當下都仍與 V1.3.1 快照相同才動手（任何一個不同就中止）。
2. 從 V1.3 備份**逐檔** `cp` 還原 7 個文字檔（shader、2 個 tres、4 支 gd），每個還原後雜湊與備份核對。
3. `bp_water_stream_head.tres`：引用檢查＝只被 `s04_boss_clearing.tscn`（第二 surface 的材質）、`terrain_generator.gd`（路徑常數）、`verify_beast_path.gd`（gate）引用，都在撤回範圍內；其他檔還原後唯一剩下的引用是尚未還原的 S04 場景。→ 刪除；副本在 V1.3.1 備份與 patch 裡。
4. **生成器輸出一致性測試**：用撤回後（＝V1.3）的程式碼跑 `generate_beast_path.gd -- --only=S04` 一次，與 V1.3 備份清單逐檔比對：341 檔裡 **339 個逐位元相同**（含全部地形、岩石、森林規劃、草叢、材質、`meta`、layout），不同的只有 2 個場景檔；這 2 個用 `evidence/scripts/sem_diff_tscn_norm.py`（把 `unique_id`、資源編號、自動命名序號正規化）做語意比對：`s04_boss_clearing.tscn` 10295 行對 10295 行、**差異 0 行**（含單一 surface 的 Water 網格），`beast_path.tscn` 30 對 30、差異 0（`evidence/logs/revert_scene_semantic_diff.log`）。
5. 再把這 2 個重生場景以 V1.3 備份**逐位元**蓋回（`unique_id` 與節點序號每次重生都會重抽，位元組一致只能靠還原原檔）。S01～S03 場景與地形資源全程沒被寫入（`--only=S04`）。

### 1.3 `water.head_material` gate 的處理

**取消（隨 `verify_beast_path.gd` 還原到 V1.3 一起移除）。原因是功能正式撤回——被驗證的東西（第二 surface、專用材質）已經不存在；不是因為驗證失敗。** 撤回前的紀錄：67 項、0 失敗，該 gate PASS，且記憶體內反向案例（surface 1 換回一般溪材質）判 FAIL（`evidence/logs/verify_s04water.log`／`.json`）。完整 gate 程式碼留在 `evidence/v13_to_v13_1.patch` 的 `verify_beast_path.gd` 段。撤回後的現行 gate 是 V1.3 原有的 66 項，沒有新增也沒有放寬任何一項。

### 1.4 撤回後驗證（最終工作區＝V1.3 位元組）

| 項目 | 結果 |
|---|---|
| 工作區 vs V1.3 備份清單（`evidence/scripts/tree_vs_manifest.py`） | **341 檔、341 相同、內容不同 0、多／缺 0**（`evidence/logs/revert_final_state.log`） |
| `verify_beast_path.gd` | **66 項、0 失敗**（60 PASS＋6 INFO）。與 V1.3 當時留下的結果（`beast_path_v13_s04_final/evidence/verify_v13_final.json`）依序逐筆比對 66 筆的 gate／ok／detail 全文：**完全相同** |
| `walk_beast_path.gd`（正式 main.tscn＋真玩家） | **7 腿、0 未到達**：403／402／83／79／35／10／148 m。與 V1.3 當時差：`branch_bamboo` 83 vs 84 m（最大上升 5.29 vs 5.30）、`branch_exit_shrine` 最大上升 1.02 vs 1.01、終點 (31.0, 15.2, −421.8) vs (30.9, 15.2, −421.8)。工作區內容與 V1.3 位元組相同，所以這些 ≤ 1 m 的差只可能來自物理取樣的執行差異，或其他 session 對玩家／main 腳本的改動（工作區 `main.gd` 等顯示 M）；兩者我沒有區分 |
| 備份完整性 | V1.3 備份 341 檔、V1.3.1 備份 342 檔，`sha256sum -c` 全部 OK |
| 殘留行程 | 沒有 Godot 編輯器或 headless 行程（`godot-ai.exe` 是 MCP 服務） |
| 其他 | 沒有 commit；沒碰 S01～S03、攝影機、BOSS 邏輯、其他 session 的檔 |

### 1.5 生成日誌 9 行資源洩漏警告（獨立技術問題）

唯讀初步定位完成，詳見 [`TECH_ISSUE_generate_only_flag_leak.md`](TECH_ISSUE_generate_only_flag_leak.md)。摘要：**與方案 A 無關**——V1.3 程式碼加 `--only=S04` 的日誌與 V1.3.1 的逐行相同（9 行、286 條警告、1583 個物件），V1.3 全量生成沒有。原因在 `--only` 過濾（`generate_beast_path.gd:76`）讓 S01～S03 已建出的道具節點從未接上樹（`:416`）、也從未 `free()`（`:474`），process 結束時成為洩漏。只影響 `--only` 路徑的結尾訊息，產物不受影響。**沒有改生成器。**

## 2. 方案 A 當時做了什麼（V1.3.1，已撤回）

- 崖頂溪（`stream_head`）的水面帶獨立成 Water 的第二個 surface，換專用材質 `bp_water_stream_head.tres`：淺水最低不透明度 0.03 → 0.50、水色偏冷偏亮、加順流細水紋（`flow_streak` 0.35）。shader 新參數預設值＝原值，其餘溪、潭、水幕渲染不變。
- 生成：`generate_beast_path.gd -- --only=S04`。
- 當時的保護核對：S01～S03 場景、6 個地形資源、S04 地形與碰撞、全部岩石網格（含 `arena_cover_0`）、森林規劃、草叢、`meta`、layout 逐位元相同（`evidence/logs/pre_*.sha`／`post_*.sha`）。
- 當時的驗證：`verify_beast_path.gd` 67 項 0 失敗；實走 7 腿 0 未到達；效能 `perf_beast_path.gd` 連跑 2 次，S04 入口 158.3／155.8 fps（V1.3 記錄 159.4）、戰場中心 161.1／161.5（161.6），GPU +0.03／+0.02 ms，draw +2／+1，圖元相同；不是同一 session 的 A/B，結論只到「沒有可測的退步」。

## 3. 玩家可達視角看得到嗎？（`visibility/V1_head_water_marked_in_magenta.jpg`、`evidence/logs/visibility_magenta_px.json`）

方法（V1.3.1 當時，用已撤回的 `mark=head`）：把 Water 的 surface 1（崖頂溪）換成不受光、不受霧的洋紅色，同鏡位拍 10:00，數洋紅像素（1600×900）。像素來自深度正確的實際渲染，已含地形、岩、樹的遮擋。

| 鏡位 | 洋紅 px |
|---|---|
| 玩家第三人稱 t01～t17、t21、t22（19 個） | 0～11（t01 8、t02 9、t04 1、t06 4、t09 9、t12 10、t14 11、t21 3，其餘 0） |
| 玩家最大仰角仰望崖頂 p01～p06（北緣 r19／r12、潭南岸、出口支線、東北出口、潭東岸；pitch 0.35～0.55） | 0～1 |
| 對照：自由鏡頭 f09／f10／f11／f12、正交俯視 o03 | 10,203／41,340／76,864／8,564／29,965（標記有效） |
| 對照：自由鏡頭 f03（崖面全景 7 m 高）／f04（戰場空拍 26 m）／f08 | 15／25／19 |

幾何上也說得通（數字為估算）：崖口水面高 32.3 m，玩家戰場地面約 12.9 m、出口支線約 15.2 m、TPS 相機最高約再 +4.4 m（人眼 1.7 m＋SpringArm 5 m × sin 0.55）；水面一律在崖口岸緣之後，從下方只會看到瀑布本身。

**未涵蓋**：玩家離開預定路線去爬戰場外圍山坡的情形。純地形（無碰撞物）洪水填充顯示外圍稜線有 y 35～52 m、坡度 ≤ 45° 的區域，在那裡看得到崖頂溪；能不能走上去取決於碰撞物／樹，沒有實測。該探針太粗（超集），留在 `evidence/scripts/probe_stream_visibility_SUPERSEDED.gd` 僅供追溯。

## 4. 畫面（上＝V1.3、下＝V1.3.1；同鏡位、同時刻 10:00，`compare/`；判讀是我用影像模型逐張比對，不是使用者審圖）

| 鏡位 | 結果 |
|---|---|
| `cmp_f11_head_along_stream`（平台人眼高度沿溪看崖口） | 明顯更像水：連續灰綠水帶、順流白紋；但白紋偏多偏長、中段一團較密 |
| `cmp_f09_falls_head`（崖頂高位俯視） | 水路與流向清楚很多、能追到崖口；流線偏平行（像細繩），崖口白色起點仍偏硬（V1.3 就有） |
| `cmp_f10_falls_lip`、`cmp_f12_lip_side_east`、`cmp_o03_falls_head_top` | 同方向的改善；河→瀑布的銜接沒變差，崖口由青灰水面跳到純白瀑布的過渡仍硬 |
| `cmp_f13_lip_from_pool`（潭邊仰視） | 看不到崖頂溪（0 px） |
| `cmp_t05_pool_waterfall`、`cmp_t06_north_wall`（玩家視角） | 無可辨差異（落水水花分佈不同是粒子動畫時刻） |

## 5. 裁定其他項（本輪都未碰）

- 不切崖口、不改北崖高度（方案 B 不執行）：未動。
- 攝影機／`arena_cover_0`／SpringArm：交專責 session，未碰；S04 場景裡 `arena_cover_0` 網格與位置與 V1.3 逐位元相同。
- 晨昏天空 → P13：未動。地表／岩壁停止迭代：未動。
- S01～S03、BOSS 功能標記、已驗證碰撞、玩家實走路線：§1.4。

## 6. 證據清單（全部保留）

- `compare/`（8 組前後對照）、`visibility/`（洋紅標記合成圖）
- `evidence/v13_to_v13_1.patch`（方案 A 的全部文字檔差異，可重新套用）
- `evidence/manifest_v13.sha256`、`manifest_v13_1.sha256`（兩份備份清單）
- `evidence/logs/`：方案 A 當時的 `gen_s04.log`、`verify_s04water.*`、`walk_s04water.*`、`perf_after_r*.json`、`pre_*.sha`／`post_*.sha`、`visibility_magenta_px.json`；撤回後的 `gen_s04_v13code.log`、`verify_v13_restored.*`、`walk_v13_restored.*`、`revert_scene_semantic_diff.log`、`revert_final_state.log`
- `evidence/scripts/`：`sem_diff_tscn_norm.py`（場景語意比對）、`tree_vs_manifest.py`（工作區 vs 備份清單）、`sem_diff_tscn.py`（舊版）、`probe_stream_visibility_SUPERSEDED.gd`
