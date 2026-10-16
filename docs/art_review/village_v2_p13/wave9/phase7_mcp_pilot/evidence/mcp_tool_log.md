# Phase 7 MCP 試行：實際呼叫的 MCP 工具與結果（2026-10-16）

## Godot AI MCP（godot-ai 4.2.1，editor PID 12976，Godot 4.7.2）
| 工具／op | 模式 | 結果 |
|---|---|---|
| `session_manage list` | R0 | 1 個 session：project `D:/神社/shrine/godot/`、current_scene `res://maps/village_v2/village_v2.tscn`、ready |
| `editor_state` | R0 | ready、stopped。**不能證明分頁沒有未存的修改**（MCP 沒有 dirty 旗標） |
| `scene_manage get_roots` | R0 | 開著 3 個分頁：`scenes/main.tscn`、`characters/yoriichi/player_yoriichi.tscn`、`maps/village_v2/village_v2.tscn` |
| `node_find`（MKT_002／_MKT_017／ArchW9R2／Camera3D） | R0 | 找到 4 棟 body、Kit、Frontage、P10 anchors、W9 enrichment；village_v2 沒有 Camera3D |
| `node_get_properties`（002・017・018・007・001・015・016 body、Kit metadata、Shape） | R0 | 位置／yaw／寬深／簷高／棟高；Kit 開間（017 戸口 x ±0.8665、018 戸口 x −0.435..1.305）；p13_role |
| `node_manage get_children`（body・Kit・Frontage・ArchW9R2P13） | R0 | **editor 記憶體中的 ArchW9R2P13 只有 40 棟（Phase 6 的 019／021／022／003 不在）＝編輯器沒有重新載入外部改過的 overlay。依規則不強制 reload、不存檔** |
| `resource_manage inspect`（017／018 Shape.shape） | R0 | 017 BoxShape 5.20×5.75×10.01、中心 y 2.525 → 頂 5.40 m；018 6.09×4.26×10.92、中心 y 1.77 → 頂 3.90 m |
| `editor_screenshot`（view_target 4 棟） | R0 | 4 張成功（`review/S1_…`）；第 1 次（2 棟同框、960 px）transport failed，改單棟 640 px 後成功。編輯器畫面有大字地標標籤，不能當美術證據 |
| `logs_read` plugin／editor | R0 | plugin 紀錄裡**另有人把編輯器切到 `maps/trail/trail.tscn` 又切回**（不是本 session 的呼叫）；editor 錯誤 1 件＝`tools/beast_path/s01_wall.gd:685` 的 Parse Error（他 session 的檔案）→ 編輯器確定有別人在用，本回全程不改不存編輯器場景 |
| `resource_manage load`（`mesh/B_P_MKT_017_L0.res`、`_018_L0.res`） | R0 | ArrayMesh、4 surface（V2_Wood／V2_Plaster／V2_Kawara／V2_MachiyaKit） |
| `project_run`（custom `village_v2.tscn`、**autosave=false**） | runtime | 遊戲行程啟動（WASAPI 無音訊裝置的錯誤 2 件＝環境）；約 39 s 後 helper live |
| `game_manage get_scene_tree／get_node_info` | runtime 讀取 | `ArchW9R2P13/B_P_MKT_017`、`_018` 各有 L0／L1；L0 mesh＝新的 .res、visible、visibility_range_end 40 m；017 L0 已複製 Kit 的 P10 校色材質（V2_Wood_K_A2 等）；**`EnrichW9P13/…/160_w9_sugidama` visible=false**（overlay 的 R1_HANG 規則把重做正面的棟的吊り物隠す）→ 發現酒屋的杉玉被藏，改為 `keep_r1` |
| `project_manage stop` | runtime | 停止（約 1 分鐘的 playing 狀態） |

沒有用到的寫入：`node_create`／`node_set_property`／`scene_save`／`scene_manage create`（W1 隔離場景也沒建）——編輯器有別人在用，且 overlay 是 generator 產物（TYPE B），在編輯器改了也不會留下。

## Blender MCP（mcp-for-blender，Blender 5.2.1 PID 17148）
| 工具 | 結果 |
|---|---|
| `get_addon_status` | **handshake 失敗**（`Connection to Blender lost: WinError 10053`、protocol null、`up_to_date: false`）。但下面的呼叫都成功 |
| `get_scene_info` | 未命名檔、Camera＋Light 2 物件（dirty＝True、空場景）。在獨立的 collection `P7_MCP_PILOT` 作業，不碰既有物件 |
| `execute_blender_code` | ① 在 live Blender 載入 `build_w9r2_arch.py`（main() 之前）＝ P4／P5／P6 builders 全部可呼叫（0.1 s）。② 匯入 Godot 匯出的實景 GLB（017／018 周圍 26 m、687 網格、約 31 萬面、3.4 s）。③ `p7_rebuild()`：exec `build_w9p7_arch.py` → 2 棟 → `to_blender` → 放到 body 的世界座標（0.4–0.6 s/次，共 5 次）。④ BVH 三角形交差：017×杉玉 16（r1：庇の桁）→ 0（r1b 庇 4.05 m）→ 11（全部＝吊り木の受け板、刻意）；017×酒の幟 0；018×全實景 0。⑤ 杉玉吊り木的端離牆 0.060 m（受け板的根據）。⑥ 結束時刪除 P7 的物件／網格／材質／collection，恢復場景相機與解析度 |
| `look`（camera／angles、solid／material／rendered） | 7 張；solid 的單棟多角度最有用（`review/M_…`）。material／rendered 的光線沒有對到遊戲（vision：「嚴重曝光不足，不能判斷材質」）→ 美術判斷改用 Godot 實機畫面 |
