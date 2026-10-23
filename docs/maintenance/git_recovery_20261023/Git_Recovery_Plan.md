# Git Recovery Plan（2026-10-23）——讓乾淨 Clone 能用 Godot 4.7.2 正常啟動

狀態：**提案，等待批准。** 本文件撰寫時沒有提交、沒有 push、沒有刪除，也沒有修改任何既有檔案；只新增了本資料夾。
基準：分支 `yoriichi-combat-and-village-routing`，HEAD `de63c17e`（ahead origin 262）。

## 0. 結論

| 問題 | 實測 |
|---|---|
| HEAD 的 `main.gd` 能否解析 | **不能**。`Parse Error: Unexpected "Indent" in class body`（第 165 行），9/24 提交 `d2cbe0a9` 起就是壞的 |
| 乾淨 clone 缺什麼 | ① 3 個執行期外掛整個被 `.gitignore` 擋在外面 ② HEAD 已追蹤的場景引用了 78 個從沒進版控的檔案（5 位 NPC 角色、字型、.uid） |
| LFS | HEAD 4,727 個 LFS 檔，本機物件 **0 缺**；從本機 repo clone 實測可下載並還原真檔（sha256 = oid）|
| 外部路徑 | 執行期 0 處；6 個資料檔裡的 `D:/…` 只是來源紀錄，不會被載入。7 個 Junction 底下的檔案都已追蹤，clone 會得到真檔 |
| 緣一 | HEAD 版 `player_yoriichi` 需要的 30 個檔案在 HEAD 裡都有（只在工作樹被刪）→ **刪除不提交，clone 就拿得到** |

需要的修補只有 4 小批，**完全不含其他 Session 對已追蹤檔案的修改**。

## 1. 分析方法（可重跑）

1. Godot 4.7.2 headless 掃全專案，對每個資源取 `ResourceLoader.get_dependencies`（UID 已解析）→ 邊表。
2. 以「clone 會拿到的版本」為準求閉包：已追蹤的文字檔讀 **HEAD 版**（`main.gd` 用最小修補版），二進位檔與未追蹤檔用 Godot 邊表。
   - 起點：`project.godot`（main_scene＋全部 autoload）、`data/<id>.meta.json` 存在的 18 張圖、`data/**/*.json`。
3. 再補三種抓不到的依賴：
   - 文字內所有 `res://` 字面路徑
   - 樣板字串（`"res://maps/%s/%s.tscn"` 等 10 種，逐一對應）
   - class_name 引用（未追蹤／忽略腳本裡的 99 個 class_name）
4. 每個節點標上 git 狀態：HEAD_clean／HEAD_dirty／HEAD_deleted_wt／UNTRACKED／IGNORED／ABSENT。

閉包共 4,814 個節點：HEAD_clean 4,382、HEAD_dirty 170、HEAD_deleted_wt 30、UNTRACKED 78、IGNORED 67、ABSENT 47、UNRESOLVED 6。
ABSENT 與 UNRESOLVED 逐筆看過：都是註解裡的文字、目錄字面、`project.godot` 啟用但已不存在的 4 個編輯器外掛，以及舊 trail／shrine／slice 場景的過期 UID（有 path 可回退）。**沒有一筆是執行期真缺檔。**

### 動態載入逐項

| 位置 | 怎麼載 | 結論 |
|---|---|---|
| `main.gd` load_map | `res://maps/%s/%s.tscn`、`data/%s.meta.json` | 起點已含 18 張圖 |
| `main.gd` | `res://blockout/%s.glb` | 只在地圖缺場景時才用；資料夾不存在，目前不會走到 |
| `npc_life_director` | `data/npc_life/%s.json` | `data/**` 已列為起點 |
| `quest_manager` | 列出 `data/quests/` | 該目錄無未追蹤檔 |
| `scene_perf_cull` | 依名字載 `_lod/<name>.glb`；引用 class `ProtonScatter` | `_lod` 無未追蹤檔；**ProtonScatter 來自被忽略的外掛 → 必須追蹤** |
| `npc_voice`、`wind` | `user://voice_cache`、`user://wind_flow_cache` | 執行期產生，不屬 repo；測試要隔離 user 目錄（見 §5） |
| `npc_life_jev_provider` | `load("res://addons/godot_jev/jev.gd")` | 外掛被忽略 → 必須追蹤 |
| `dialogue_manager`、`npc_visual`、`ambience` | 路徑來自 json／常數表 | 已含在字面掃描 |

## 2. 417 → 78：未追蹤執行期檔案分類

先前的 417 是以**工作樹**程式求的。以 HEAD 程式求，真正必要的只有 78。

| 類別 | 檔數 | 大小 | 說明 |
|---|---|---|---|
| A　HEAD 已追蹤場景直接需要 | 78 | 133.8 MB | 清單見 `head_required_untracked_78.json` |
| B　本輪新地圖接管 | 16 | 1.2 MB | 不屬於還原批次 |
| C　只有其他 Session 的新程式才需要 | 323 | 171.1 MB | 緣一 84、village_v2 素材 75、角色動畫 87、ui/gensokyo、背包、冥想、時間…… **不提交** |

A 類 78 檔細分：

- **R3a：12 個 `.uid`**，都屬於已追蹤的腳本或 shader。
  - 缺了的話 Godot 會重新配發 UID，以 UID 引用的場景就會斷。
  - 純中繼資料。
- **R3b：65 檔，133.8 MB**，給 HEAD 的 `maps/village_v2/{akyuu,keine,kosuzu,marisa,reimu}_npc.tscn` 與 `village_v2.tscn` 用：
  - 角色：阿求 19、魔理沙 13、慧音 11、小鈴 9、靈夢 9、`npc/_shared` 2
  - 字型：`NotoSerifTC-VF.ttf` 16 MB
  - 其中 **13 個是程式或場景**（`.tscn`／`*_visual.gd`／袖子、裙子腳本），由其他 Session 在 10/18～10/21 建立。這些是「他人建立的新檔」，不是對已追蹤檔的修改。
  - 經檢查，它們沒有直接依賴任何 dirty 的已追蹤檔。
- **排除**：`maps/village/village.tscn`（210 bytes 轉接檔）。HEAD 沒有任何傳送門以 `village` 為目標。

## 3. 被忽略的 `addons/`

`.gitignore` 第 29 行整個忽略 `godot/addons/`，理由是「godot-mcp 每次啟動會覆寫」。實際查 `D:\godot-mcp\plugin\addons`，裡面**只有 `godot_ai`**，另外 3 個外掛沒有其他權威來源：

| 外掛 | 誰在用（HEAD） | 缺了的後果 | 檔數／大小 | 授權 |
|---|---|---|---|---|
| simplegrasstextured 2.1.0 | autoload `SimpleGrass`、slice 草 | autoload 失敗，slice 載不起來 | 122／0.5 MB | MIT |
| proton_scatter 4.2.0 | slice `river_vegetation`、`scene_perf_cull`（class ProtonScatter） | 腳本編譯失敗、slice 植被缺 | 418／11.9 MB（`demos/` 佔 83 檔 11.2 MB，非執行期） | MIT |
| godot_jev 1.0 | `npc_life_jev_provider` 執行期 load | 決策提供者啟用時載不到 | 30／0.1 MB | MIT |
| godot_ai 4.2.1 | autoload `_mcp_game_helper`（MCP 偵錯用） | autoload 報錯一次，遊戲繼續 | 311／2.1 MB | MIT，**來源是 godot-mcp，維持忽略** |

另有 `CyclopsAutoload="*uid://4siqre3jhe80"`：外掛本體在任何地方都不存在，是死引用。工作樹版的 `project.godot` 已刪掉同一行。

## 4. `main.gd` 最小修補（`main_gd_minimal_fix.patch`）

HEAD 第 165 行 `var _shot_hidden_ui: Array[CanvasLayer] = []` 沒有縮排，被插在 `_load_json_array()` 的函式體中間。後面縮排的程式因此全部成為「class body 裡的 Indent」。同一次編輯還把「藏 HUD」的區塊插進了 `for hp` 迴圈裡。

修補 3 段、淨 +4／−4 行，**與工作樹現有內容逐字相同**（取自工作樹 diff 的第 6～8 段），之後其他 Session 提交時不會衝突：

1. 把那行移到模組層（`_shot_hidden` 之後）。
2. 移除被切斷的 `if map_root != null: for hp …` 開頭。
3. 把它接回 HUD 區塊之後。

實測（Godot 4.7.2 `--check-only`）：
- HEAD 版：Parse Error。
- 修補版：`main.gd` 本身無解析錯誤。剩下的是 `Identifier not found: DialogueManager／QuestManager`，屬 `--check-only` 不註冊 autoload 的已知誤報（`tools/dev/gd_check.py` 文件有記載）。真正的確認放在乾淨 clone 的開機測試。

## 5. 提交批次（每批都用臨時索引，不碰真實索引裡的 53 筆）

| 批 | 內容 | 檔數 | 寫法 | 單批驗證 |
|---|---|---|---|---|
| R1 | `main.gd` 最小修補 | 1 | 以 HEAD blob＋patch 產生 scratch 版、`hash-object` 進臨時索引；**工作樹的 main.gd 不動** | `git diff HEAD~ HEAD` 恰好 3 段；clone 內 `--check-only` 無 Parse Error |
| R2 | ① `.gitignore`：`godot/addons/` 改為 `godot/addons/*`＋放行 3 個外掛＋忽略 `proton_scatter/demos/` ② 3 個外掛（487 檔、約 1.3 MB；其中 png 走 LFS）③ `project.godot`：以 HEAD 為底只刪 `CyclopsAutoload` 一行 | 約 490 | `.gitignore`、`project.godot` 用 scratch blob；工作樹的 `project.godot`（他人修改）不動 | clone 內 SimpleGrass autoload 成功、`river_vegetation.tscn` 載入、`scene_perf_cull.gd` 編譯通過 |
| R3a | 12 個 `.uid` | 12 | 直接加 | clone 內這些 UID 解析到原路徑 |
| R3b | 65 個角色／字型檔 | 65 | 提交前對每檔做兩次間隔 SHA-256；任何一檔變動就中止 | clone 內 5 位 NPC 場景實例化、動畫數 > 0 |

提交後只重設這些路徑的真實索引項，並逐筆比對原本 53 筆 staged 的 mode／blob，確認完全一致。

**不在還原批次裡**（維持現狀）：
- 170 個其他 Session 修改的已追蹤檔
- C 類 323 個未追蹤檔
- 本輪新地圖接管（B 類＋本輪改的 5 個已追蹤檔）
- 293 個工作樹刪除＋53 筆 staged 刪除
- `.hermes.md`、`.claude/rules/efficiency.md`、`docs/PROJECT_STATE.md`
- `docs/reference`、`docs/art_review`
- `godot_ai`

## 6. 乾淨 Clone 驗證程序（R1～R3b 全部提交後，跑一次完整版）

1. `git clone --no-hardlinks D:/神社/shrine <scratch>/clean_<commit>`。LFS 端點會是本機 `.git`，已實測可用。
2. LFS：
   - 掃全部 LFS 檔，指標檔（`version https://git-lfs` 開頭）必須 = 0。
   - `git lfs fsck` 逐檔核對 sha256 = oid。
3. 隔離：
   - clone 內不放 `godot/addons/godot_ai`。
   - 新增**只存在 clone**、不提交的 `override.cfg`，讓 `user://` 改到獨立資料夾，避免讀到原專案的語音／風場快取。
   - 不複製 `.godot/`。
4. `--headless --import`：記錄耗時；log 中 `Failed loading`／`Missing dependencies`／`Cannot open file` 必須 = 0。
5. `--check-only res://scripts/main.gd`：無 Parse Error。
6. 開機 `main.tscn` 跑 600 幀，搭配 `--verbose`：
   - `SCRIPT ERROR` = 0。唯一允許的是 `_mcp_game_helper` 這個 autoload 失敗，已在 §3 說明。
   - verbose 載入紀錄中所有路徑必須是 clone 內的 `res://` 或隔離的 `user://` → 證明不依賴原工作目錄或外部路徑。
7. 冒煙腳本（只複製進 clone、不提交）：
   - 實例化 `characters/reimu/reimu.tscn`、`characters/yoriichi/player_yoriichi.tscn`、阿求／慧音／小鈴／魔理沙：網格數 > 0、動畫數 > 0、播待機 30 幀無錯。
   - 經 `main.load_map` 載入 `village_v2`、`beast_path`、`shrine_v3`：出生點向下射線有地面。
8. 傳送：跑 HEAD 版 `tools/portal_test.gd`（HEAD 現有的門與連線）。三張新圖之間的互通屬於「新地圖接管」批次，不在 HEAD 範圍，接管提交後再用同一流程測一次。

預估成本：
- clone：約 7 GB（6.4 GB LFS＋0.8 GB blob）。
- 全專案匯入：原專案 `.godot` 約 4.5 GB，預計 30～90 分鐘，以實測為準。
- 硬碟剩 369 GB。

建議另加一個 **R0 基準**：提交前先對目前 HEAD 跑同一套第 1～8 步，留下「修補前」的失敗清單，修補後逐項對照。

## 7. 其他風險

- **遠端**：origin 落後 262 個提交，這些提交的 LFS 物件目前只在本機 `.git/lfs`（6.8 GB）。從 GitHub clone 拿到的是舊版；push 前要先 `git lfs push --dry-run` 並確認 LFS 額度。本計畫不 push。
- 本機 `.git/lfs` 是唯一副本，建議另做離線備份（例如 bundle＋lfs 物件複製；不動歷史）。
- **緣一刪除**：工作樹刪的 105 檔中，有 30 個是 HEAD 版 `yoriichi_character.gd`／`player_yoriichi.tscn` 直接需要的。在隔離區與 `D:/神社_archive` 都找不到，只有 git 歷史有。維持不提交刪除，clone 就完整。
- **其他 Session 仍在寫**：今天 14:03～16:43 還有 `characters/yoriichi/v24_isshin/**` 與 `docs/plans/2026-10-23-日之呼吸動作規劃.md` 在變動，與 R1～R3b 範圍不重疊。R3b 的 65 檔最後修改在 10/21 17:34 之前。
- **Junction**：clone 會把 7 個 Junction 變成真實資料夾，內容來自 git。原工作樹若有人改了外部資產庫，會在原 repo 顯示為修改。

## 8. 設定與文件（只盤點，不提交）

| 檔案 | HEAD 版 | 工作樹差異 | 最後寫入 | 來源判讀 |
|---|---|---|---|---|
| `.hermes.md` | `0fde0a38`（10/22） | −98／+46 行：刪「Human Village V2 Phase Authority」與「Free Execution Workflow」；加「風力系統／緣一動作／打擊感／NPC 互動」必讀清單、角色動畫 Skill 規則、「效率規則（10/18）」、「JEV 獨立審查協議」 | 10/23 14:01 | 新增段落從未出現在任何提交（`git log -S` 為空），是工作樹上的手改；本 Session 沒寫過此檔。工作樹版就是目前各代理實際載入的憲章 |
| `.claude/rules/efficiency.md` | `3f5d8f4c`（10/18） | +4：第 6 條「獸道單區迭代 bp_iterate.sh」 | 10/18 02:38 | 與 `.hermes.md` 效率規則第 6 條同文，同一批手改 |
| `docs/PROJECT_STATE.md` | `8e73cf17`（9/18） | 1 段：「圍牆佈局計畫」改為「9/23 使用者撤回」 | 9/23 16:58 | 對應 9/23 的使用者裁定 |

## 9. `docs/reference`（只盤點，不進 Git、不刪）

148 檔，309 MB（另有 11 檔已追蹤）。清單見 `docs_reference_inventory.json`。

- **76 檔（162 MB）的檔名被規格、計畫或工具引用**：重建時的必要參考。
- **72 檔（148 MB）沒有任何文件按檔名引用**：所屬資料夾多半有被引用，需要逐張確認。
- **3 組完全相同的檔案**（`民宅/` 下：一般市集商店＝普町3、中等町2＝普町2、普町4＝高等町4）。
- 檔名看不出生成器的中間版本（沒有 ChatGPT／Gemini／draft／v2 等字樣），中間版只能逐張判斷。
