# Git Recovery 執行報告（2026-10-23）

狀態：**RECOVERY COMPLETE（核准範圍內）**。乾淨 clone 能用 Godot 4.7.2 匯入、啟動並跑滿 600 幀；角色、字型、三張新版地圖、舊版傳送路線都通過。
仍有 3 項「非還原造成」的既有缺陷與 2 項未核准的小補充，見 §6。沒有 push、沒有提交刪除、沒有改寫歷史、沒有清理 LFS。

## 1. 備份（先於任何提交）

位置：`D:\神社_archive\git_backup_20261023\`（12 GB，不在任何清理範圍內）

| 內容 | 檔案 | 驗證 |
|---|---|---|
| 全部 15 個 refs 與歷史 | `shrine_all_refs.bundle`（607 MB） | `git bundle verify` okay |
| stash@{1}（只在 reflog，bundle 帶不到） | `stash1_untracked.tar`＋`stash1_ids.txt`（tracked／index 差異為空） | tar 可讀，38 項 |
| LFS 物件 | `lfs_objects/`（4,827 個，6.7 GB） | 每個 SHA-256＝檔名，0 壞 |
| 未提交工作 | `worktree/`＋`worktree_manifest.json`（9,235 檔、3.9 GB；另記 293 個工作樹刪除） | 重算 SHA-256，0 不符 |
| 真實索引與狀態 | `git_index.bin`、`ls_files_stage.z`、`status_porcelain.z`、`staged.patch` | — |
| 還原後新增的 4 個提交 | `recovery_commits_R1-R3b.bundle`（前置 de63c17e）＋其 44 個新 LFS 物件 | `git bundle verify` okay |

**還原實測**：
1. 從 bundle clone，再從備份複製 LFS 物件後 checkout。
2. 結果：HEAD `de63c17e`，15 個 refs 全部一致；4,727 個 LFS 檔沒有任何一個停在指標檔；`git lfs fsck` OK；`git status` 乾淨。這份還原直接當作 R0 基準。

已知缺口：
- 舊分支（main、backup/*、origin/* 舊 tip、stash）引用的 LFS 物件有 186 個，本機原本就沒有，可能只存在 GitHub。
- 目前分支 HEAD 與 262 個本機提交引入的 3,600 個 LFS 物件，備份裡全部都有。

## 2. R0 基準（修復前 HEAD `de63c17e`，乾淨還原）

| 項目 | 結果 |
|---|---|
| 匯入 | exit 0、732 s；共 11 類錯誤：main.gd Parse Error、`Unrecognized UID uid://4siqre3jhe80`（Cyclops）、SimpleGrass singleton 載入失敗、`_mcp_game_helper` 找不到 |
| `main.gd` | `Parse Error: Unexpected "Indent" in class body` |
| 開機 120 幀 | main.gd 載入失敗 → `Invalid access to property 'map_root'` ×255、玩家座標非有限值 ×218；3 個 autoload 建立失敗（SimpleGrass、_mcp_game_helper、Cyclops） |
| 外掛 | simplegrasstextured、proton_scatter、godot_jev 全缺（`river_vegetation.tscn` 載不起來） |
| 角色／字型 | 靈夢、阿求、慧音、小鈴、魔理沙 5 個場景全部載入失敗；`NotoSerifTC-VF.ttf` 不存在；npc_life 資料引用的 12 個動畫中 12 個缺檔 |
| 能載入的 | 緣一（網格 6、動畫 27）、village_v2／beast_path／shrine_v3 場景本體、9 個任務 |

日誌：`D:\神社_recovery_test\r0_logs\`

## 3. 提交（臨時索引＋plumbing；真實索引只校正提交路徑，53 筆 staged 每批逐位元組不變）

| 批 | Commit | 檔數 | 內容 |
|---|---|---|---|
| R1 | `7a27e58b` | 1 | `main.gd` 3 段（+4／−4），與工作樹逐字相同。只修第 1 段仍會 `Parse Error: Identifier "hn" not declared`（已實測） |
| R2 | `614e081f` | 489 | `.gitignore`（放行 3 外掛、demos 仍忽略）＋外掛 487 檔＋`project.godot` 只刪 2 行 autoload（Cyclops、`_mcp_game_helper`；godot_ai 外掛啟用時會自行寫回） |
| R3a | `361a79f4` | 12 | 已追蹤腳本的 `.uid`，取自工作樹、未重新生成；每個 UID 全專案唯一 |
| R3b | `7bbd8e74` | 138 | 見下 |

完整檔案清單：`committed_files_R1-R3b.json`。

R3b 比原核准的 65 檔多 73 檔。原因是我原先的分析漏了兩類依賴，兩類都屬於核准範圍內的這 5 位角色：

- **31 張角色貼圖＋各自的 `.import`**：glb 匯入時抽出的外部貼圖。原因是第一次的 Godot 邊表探針路徑寫錯（`res:/`），結果為空，只剩文字解析，二進位依賴漏掉。修正後改用 R0 乾淨 clone 量得的 HEAD 版邊表重算，才補上。
- **11 個動態載入檔**：袖子／裙擺模擬以 `data_prefix + "_colliders.json"`、`"_sleeve_chains.json"`、`"_skirt_chains.json"`、`"_sleeve_L/R.glb"` 載入，靜態閉包抓不到，是逐一讀程式找出來的。

穩定性檢查（R3b 的 138 檔）：
- 16:55 快照、17:4x 快照、提交當下兩次雜湊（間隔 5 秒），全部一致。
- 最後修改時間是 10/21 17:34；這些資料夾 24 小時內沒有任何寫入。
- 另一個 Session 當時正在寫 `characters/yoriichi/v24_isshin/**`，與 R3b 不重疊。

R3b 的 9 支 `.gd` 經 gd_check 全部 PASS；依賴都落在 HEAD 或 R3b 本身；沒有修改任何已追蹤檔。

工作樹沒有被覆蓋：唯一寫入工作樹的是 `.gitignore`（原本乾淨，內容＝R2 提交版）。`main.gd`、`project.godot` 的工作樹版本（其他 Session 的修改）原封未動。

## 4. 最終乾淨 clone（`7bbd8e74`，`git clone --no-hardlinks D:/神社/shrine`）

| 項目 | 結果 |
|---|---|
| LFS | 4,778 檔，沒有任何一個停在指標檔；`git lfs fsck` OK；端點是本機 `.git` |
| clone 內容 | `git status` 0 行；`addons` 只有 godot_jev、proton_scatter、simplegrasstextured（不含 godot_ai） |
| 匯入 | exit 0、794 s。只剩 5 個 WARNING：`project.godot` 啟用但不存在的編輯器外掛（asset_placer、cyclops、meshy、terrain_3d、godot_ai），僅影響編輯器 |
| `main.gd` | 無 Parse Error；只剩 `--check-only` 不註冊 autoload 的已知誤報 |
| 開機 600 幀（--verbose） | 0 個 SCRIPT ERROR、0 個 autoload 錯誤；只有結束時的 `resources still in use`。載入的 438 個資源全部是 `res://` |
| 角色 | 靈夢（網格 11／動畫 4）、阿求（7／8）、慧音（8／4）、小鈴（7／15）、魔理沙（5／8）、緣一（6／27），各跑 30 幀 |
| 字型 | NotoSerifTC-VF 能排版「幻想鄉緣一」 |
| 三張新版地圖 | `main.load_map` 載入 village_v2、beast_path、shrine_v3 全部成功；直接開機 playtest 的出生點：village_v2 見 §6、beast_path 0.00 m、shrine_v3 0.00 m |
| 傳送 | HEAD 版 `portal_test.gd`：**PASS 10 hops＋執行期路線 trail→slice→kourindou→slice→trail** |
| 動態載入 | `data/quests` 列舉 9 個、0 失敗；4 份 npc_life JSON 都能解析，引用的動畫全部存在 |
| 全專案 gd_check | 1,114 檔：PASS 1,113、FAIL 1（`tools/p11r2/player_camera_adapter_p11r2.gd` 與父類常數重名；工具腳本，R1～R3b 都沒碰，屬既有問題） |
| 冒煙總計 | PASS 36／FAIL 2：一項是我的正則把 `voices.json` 註解裡的「res://assets/voice（…」當成路徑（誤報）；一項見 §6-3 |

日誌：`D:\神社_recovery_test\final_logs\`

匯入後 clone 內出現的變動（都是 Godot 自動產生，不是缺檔）：
- 1,937 個 `.import` 只有換行差異（`--ignore-cr-at-eol` 下 0 差異）。
- 219 個 `.uid`：已追蹤但從未提交 `.uid` 的腳本，由 Godot 重新配發。
- 2 張袖子 glb 抽出的貼圖。

## 5. Git 安全

- 臨時索引的 porcelain `git commit` 會卡住：臨時索引沒有 stat 快取，commit 時要對整個 7 GB 工作樹重算 LFS clean。第一次因此逾時，HEAD 沒有變動，只刪除了臨時索引與它的 lock。之後改用 `write-tree`＋`commit-tree`＋`update-ref`（只有 `git lfs post-commit` 這個 hook，它只處理檔案鎖）。
- 每批提交後的檢查：name-status 與預期逐檔相符、其他索引項 0 變動、staged 53→53 且集合相同、提交路徑全部對齊新 HEAD。
- 沒有 push、沒有提交任何刪除、沒有改寫歷史、沒有清理 LFS、沒有修改其他 Session 的檔案。

## 6. 仍需處理

1. **未核准的小補充（R3a-2，5 檔）**：`maps/village_v2/scripts_p10/road_base.gd.uid`、`scripts_p13/{hillfoot_precinct_e2,lod_cal_batch,lod_guard}.gd.uid`、`shaders_p10/falling_water_p10.gdshader.uid`。
   - 這 5 個腳本經由 HEAD 的二進位場景引用，R3a 盤點時漏掉了。
   - 乾淨 clone 會配發不同 UID（例：road_base 工作樹是 `ivseo41huk16`，clone 是 `babmgajy8m066`），目前靠路徑回退運作，沒有錯誤。
   - 建議比照 R3a 提交，待批准。
2. **既有缺陷（非還原造成，修正都在未提交的地圖接管工作裡）**：
   - village_v2 出生點與傳送點被袖子模擬的 `Floor`（y=1.69）誤判為埋地 1.3 m。
   - 三張新版地圖都沒有環境音。
3. **既有行為**：在同一幀連續以 `load_map(id, "")` 換圖時，beast_path 出生點被放在 20.7 m 高（射線打到前一張圖還沒釋放的碰撞）；直接開機到 beast_path 時是 0.00 m。R1～R3b 都沒有動載圖程式。
4. `project.godot` 仍啟用 5 個不存在的編輯器外掛（只影響編輯器 WARNING）。依指示未改其他設定。
5. 工作樹 `project.godot` 仍含 `_mcp_game_helper`（godot_ai 外掛會寫回）。日後若整份提交工作樹版，乾淨 clone 會再出現那個 autoload 錯誤；提交 `project.godot` 時要排除這一行。
6. 新版三圖之間的互通（獸道↔神社、人里↔稗田邸／香霖堂）、靈夢進神社，都還在未提交的地圖接管工作中，不在本次 HEAD 裡。
7. 遠端落後 262 個提交；這些提交的 LFS 物件只在本機與本次備份中。
