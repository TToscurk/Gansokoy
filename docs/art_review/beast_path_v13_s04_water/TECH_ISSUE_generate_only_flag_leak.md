# 技術問題（獨立紀錄）：`generate_beast_path.gd -- --only=<場景>` 結束時的資源洩漏警告

- 狀態：**OPEN／未排程／低嚴重度**（只在 process 結束時印警告，產物不受影響）
- 發現：2026-10-15，獸道 S04 方案 A 測試時（`--only=S04` 生成日誌多出 9 行 ERROR）
- 本輪處理：**只做唯讀初步定位，沒有改生成器**（使用者指示）。這個問題與方案 A 無關（見下表 B 對照）。

## 症狀

`godot --headless --path godot --script res://tools/beast_path/generate_beast_path.gd -- --only=S04` 正常完成（exit 0、`[gen] 完成`），但結尾多出：

- 9 行 `ERROR`：`Pages in use exist at exit in PagedAllocator`、`69 RID allocations of type 'P11GodotBody3D' were leaked`、`165 … P12GodotShape3D`、`113 … DummyMaterial`、`4 … DummyShader`、`287 … DummyMesh`、`2 … DummyTexture`、`600 … InstanceE`、`9 resources still in use at exit`
- 286 行 `WARNING: Leaked instance dependency`
- `1583 ObjectDB instances were leaked at exit`

整份日誌 602 行；V1.3 全量生成（不帶 `--only`）的日誌只有 18 行、沒有任何洩漏訊息。

## 對照實驗（同一台機器、同一天）

| 組 | 程式碼 | 指令 | 洩漏行 | 日誌 |
|---|---|---|---|---|
| A | V1.3 | 全量（`regen13.sh`，不帶 `--only`） | **0** | `beast_path_v13_s04_final/evidence/logs/v13_r9a.log`（18 行） |
| B | V1.3.1（方案 A 已套用） | `--only=S04` | **9**（286 條 dependency 警告、1583 ObjectDB） | `evidence/logs/gen_s04.log` |
| C | V1.3（方案 A 已撤回） | `--only=S04` | **9**（286、1583，與 B 逐行相同，只差耗時） | `evidence/logs/gen_s04_v13code.log` |

B 與 C 去掉耗時後 `diff` 為空 → 與方案 A 的程式碼無關；是否帶 `--only` 決定有沒有洩漏。

## 定位（讀 `tools/beast_path/generate_beast_path.gd`，唯讀）

1. `_initialize()` 在 `:57-58` 為**每個**場景建一個 `_poi_nodes[sid] = []`，接著 `_build_pois()`（`:59` 起）把所有場景的道具節點（`StaticBody3D`＋`MeshInstance3D`＋`CollisionShape3D`）都建出來，`:113`／`:149`／`:280` 依道具位置的 z 放進各場景的陣列。**此時它們都是沒有父節點的孤兒節點。**
2. 道具節點唯一被接上樹的地方是 `_build_scene()` 的 `:415-416`（`for n in _poi_nodes[sid]: pr.add_child(n)`），之後 `:474` 的 `root.free()` 連同子節點一起釋放。
3. `:75-77` 的 `--only` 過濾 `if only != "" and sc.id != only: continue` 讓 `_build_scene()` 對其他場景整個略過 → S01～S03 的 `_poi_nodes` 從來沒被接上樹、也沒被釋放，process 結束時成為洩漏的孤兒節點。
4. 數量級吻合（**不是逐項對帳**）：S01～S03 的場景檔裡 `StaticBody3D` 33＋16＋22＝71、`MeshInstance3D` 194＋196＋218＝608、`CollisionShape3D` 69＋51＋61＝181，各含每個場景自己的地形節點（`TerrainBody`／`TerrainMesh`／`TerrainShape` 各 1，不在 `_poi_nodes` 裡）；洩漏的 Body 69、Instance 600、Shape 165。全量生成日誌的 `props` 欄位 S01 22／S02 27／S03 26 共 75 組道具，S04 76 組。

## 影響

- **產物沒有影響**：C 組（V1.3 程式碼＋`--only=S04`）重生之後，全部 341 個檔裡 339 個與 V1.3 備份逐位元相同；其餘 2 個是場景檔（見下一點）。
- 同源的另一個副作用：`--only=S04` 產生的 `s04_boss_clearing.tscn` 與全量生成相比，自動命名節點的序號不同。實測：V1.3 場景檔裡自動命名序號是整個 process 共用的遞增計數（S01 從 `MeshInstance3D_12` 起、S02 從 `_228`、S03 從 `_438`、S04 從 `_700`），`--only=S04` 時 S04 從 `_1` 起（機制沒有深究，只記觀察）；`unique_id` 每次重生本來就會重抽。語意比對（`evidence/scripts/sem_diff_tscn_norm.py`，把編號與後綴正規化）差異 0 行，沒有任何 gate 依賴這些名稱。
- 只有 `--only` 路徑會遇到；全量生成（V1.3 的正式流程）沒有。

## 建議（本輪沒做；要做另開工作）

- 在 `_initialize()` 場景迴圈後，把 `only` 模式下沒有被消耗的 `_poi_nodes[sid]` 逐一 `free()`（約 3 行），或在 `--only` 時整個略過對應場景的道具建構。
- 驗收：`--only=S04` 的日誌洩漏行數 0；`maps/beast_path/gen/` 其他檔的雜湊與全量生成相同。
- 不處理的風險：`--only` 之外沒有影響；若不使用 `--only` 可以完全不處理。

## 未驗證

- 第 4 點的數量只是同一數量級，沒有逐項對帳。
- 沒有做「釋放孤兒節點後洩漏消失」的對照實驗（需要改生成器，違反本輪「不要擅自重構生成器」）。

## 追加（2026-10-16，S01 R1）：`--only=S01` 同樣出現，產物不受影響

- 指令：`generate_beast_path.gd -- --only=S01`（`beast_path_s01_r1/evidence/gen_r1_restored2.log`）。
- 結尾訊息與上表 B／C 同一類：487 條 `Leaked instance dependency`、9 行 `ERROR`（`Pages in use`、各類 `RID allocations ... leaked`）、`2484 ObjectDB instances were leaked`、`14 resources still in use`。數字比 `--only=S04` 大是因為 S01 以外的 S02／S03／S04 道具節點全部成了孤兒（與 `--only=S04` 時 S01–S03 成孤兒同理，推測；本輪仍未改生成器、未逐項證實）。
- 產物不受影響的證據：同一輪的 `s01_terrain.res`、`forest_plan.json`、`s01_forest_inputs.json`、`bp_ground_s01.tres` 與跑之前的備份逐位元相同；`s01_entrance.tscn`、`beast_path.tscn` 語意比對 0 差異（`tools/beast_path` 之外的 S02／S03／S04 檔案本來就不被 `--only=S01` 寫入，且與 V1.3 備份逐位元相同）。
- 狀態不變：OPEN／未排程／低嚴重度。
