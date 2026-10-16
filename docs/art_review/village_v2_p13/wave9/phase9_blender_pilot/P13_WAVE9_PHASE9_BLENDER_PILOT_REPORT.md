# P13 W9 Phase 9｜Blender-first 街區管線 試點 B8P（ART_REVIEW）

> **狀態：ART_REVIEW（未核准、未封存、未掛載、未 push）。** gate PASS 與 AI vision 分數都不是美術品質的證明。
> **使用者裁定（2026-10-16 收尾）：** 管線技術上可行；B8P 保留為隔離實驗，不取代 B8、不與 B8 同時掛載、不再打磨。§7 的「需要使用者裁定」已由此結案。
> 試點 overlay `DistrictB8P` 只在隔離場景與記憶體掛載中執行；`village_v2.tscn`、`layout_v2.json`、`B8.json`、`district_b8.scn` 逐 byte 未變（sha256 對照 `owned_before.sha256`）。原 53 個 staged 項目 `diff --cached --raw` hash 與開工前相同。
> Blender：使用者開了兩個 Blender，本輪只連 **9876（PID 17148）**，每次操作前以 MCP 回報 PID 確認；結束時該 session 已還原為開工時狀態（Camera＋Light、0 mesh）。

## 0. 結論

1. **管線可用**：Godot → Blender 參考 → Blender 編排 → manifest → Godot bake → 驗證，一圈實際跑通 6 輪（校正＋r1–r5）。單一物件修改的增量循環：Blender 改＋檢查＋匯出 **0.07 s**，Godot 只重 bake `district_b8p.scn` **11.0 s**，只驗改動項的 gate **11.6 s**；其餘 186 棟建築與其他 overlay 不重建。
2. **座標換算已用旋轉＋非均勻縮放物件實測**：3 棟既有建物（yaw −132.0°／−132.0°／−161.6°，mesh0 scale 5.4×0.69×10.01）在 Blender 中頂點 world AABB 與 Godot 差 ≤ **0.21 mm**；試點 62 件 runtime 頂點 AABB 差 ≤ **0.15 mm**。容差由校正回圈先定（runtime 2 mm、參考 3 mm），之後未改。
3. **工程面最終**：gate 14 PASS／0 FAIL、反向案例 8／8；真玩家輸入實走 15 腳 ON／OFF 皆 0 FAIL；SpringArm 嚴重縮短 0；浮空 0；三角形實貫通 0。
4. **美術面誠實結論**：比 P8 **略好，不是明顯好**。後院共享地（V3，畫面占 8 %）生活感最明顯；巷口（V1）與住宅列（V4）在 TPS 視角裡仍偏空，部分道具像「擺上去」而非用出來的。兩輪修正額度已用完，剩餘問題列在 §6。
5. **建議**：此流程可以取代逐件 GDScript planner 作為後續街區的施工方式（§7），但「生活感」的瓶頸在資產種類與敘事密度，不在工具。

## 1. 交付物

| 項目 | 位置 |
|---|---|
| A. Blender 工作場景 | `work/district/B8P/B8P.blend`（291 MB，未入庫）：`REFERENCE_EXISTING_VILLAGE_B8P`（999 件，`hide_select`，不匯出）＋`DISTRICT_B8P_WORK`／`STRUCTURES` 22・`PROPS` 31・`VEGETATION` 9 |
| B. 匯出／匯入工具 | `godot/tools/district/`：`district_context.gd`（Godot→Blender 參考）、`district_blender.py`（Blender 端載入／放置／檢查／匯出）、`district_build.gd`（manifest→overlay bake）、`district_verify.gd`（gate）、`district_lib.gd`（街區定義・共用） |
| 試點資料 | manifest `godot/data/district/B8P.json`（62 件，sha256 `1236c222…`）→ overlay `godot/maps/village_v2/gen/district_b8p.scn` → 隔離場景 `godot/tests/district/district_b8p_test.tscn` |
| C. 驗證結果（機器可讀） | `evidence/b8p_pilot_summary.json`；細項 `verify_final.json`、`ref_validation.json`、`cal_verify.json`、`incr_verify.json`、`walk_ON.json`／`walk_OFF.json`、`perf_b8p.json`、`seal_check.txt`、`GATE_HISTORY.txt` |
| D. 視覺證據 | `review/B8P_before_p8_pilot.jpg`（BEFORE／P8／PILOT × 5 個 TPS 鏡位＋1 高位診斷，相機座標三態差 ≤ 0.012 m）；`review/B8P_iteration_r2.jpg`（第一輪修正前）；`review/B8P_plan_map.png`（平面圖） |
| JEV | `evidence/jev_w9bf_summary.md`：28 案 27 符合（T22 判得更保守，兩者都表示不做） |
| 重現 | `evidence/repro/`（拍攝、實走、效能、比較圖、平面圖、JEV 腳本） |

## 2. 座標與 pivot 約定（唯一一次換算）

- manifest／context 一律 **Godot world、Y-up、公尺**（`space = godot_world_y_up_m`）；Blender 只在 `district_blender.py` 的 `g2b()`／`b2g()` 換算：Godot `(x, y, z)` ↔ Blender `(x, −z, y)`；yaw ↔ `rotation_euler.z`；scale `(sx, sy, sz)` ↔ `(sx, sz, sy)`。
- Pivot＝資產 BASE 原點（底面中心）。bake 時節點 transform 只套一次；Y 由 Godot 依真實地形重新接地，與 Blender 的差最大 0.014 m，M5b 只補這一次差量。
- 反向案例確認以下錯誤會被抓到：`space=blender_z_up`、AABB 沿 z 偏 0.3 m（軸換算錯）、runtime 節點偏 0.3 m、抬高 0.3 m（浮空）。

## 3. 試點內容（B8P：RNE_002／003／004 三戶與後院共享地，rect 442,−241 起 33×31 m）

- 62 件＝沿用 P8 B8 的 33 件（保留原 vid 於 `src`）＋Blender 新放 29 件，全部是既有資產、獨立節點、無 MultiMesh、無新網格。
- 新增按住戶用途編組：002 後門洗衣（盥・手桶）、002 分岔側壁的薪（2 堆不同長度）與藁塚、003 劈柴場（薪割台・薪・材木）、004 菜園（畦 2・大根干し・鍬・背負籠・俵・苫）、共同干し場（稲架・籾干し筵・俵・藁束）、邊界（柴垣 2・笹・若杉）、003↔004 間踏石小徑 4。
- 沒有新增大型或有劇情功能的建物（JEV T22 情境同此）。

## 4. 驗證結果

| 項目 | 結果 |
|---|---|
| 匯出／匯入件數 | Blender 匯出 62 → overlay 節點 62（M3 往復 x/z/yaw/scale 不一致 0）；MeshInstance 136、碰撞 33、LOD0 三角形 30,521 |
| World AABB | 62 件頂點 AABB：min 差 0.11 mm、max 差 0.10 mm、尺寸差 0.15 mm（容差 2 mm） |
| 重疊 | footprint 初篩候補 0 組 → 三角形實貫通 0 組；道・建物・戶口・水・田・封存物・NPC・Hero 禁區觸碰 0 |
| 地形接地 | TerrainCollision 多點 ray 513 本、59 件：浮空 0、最低支持率 100 %、最大埋入 0.02 m；6 件站在無碰撞的可視地面（店先帶 4、院子 2）上，另行標記 |
| SpringArm | 3 條通行帶 14,480 樣本：嚴重縮短（≥ 2.0 m 且臂 < 3.0 m）0；≥ 0.30 m 的縮短 6 處，最差 7.50 → 3.30 m（NELane 462.1,−236.7） |
| 實走（真玩家輸入） | 15 腳（巷 4、NESouth 2、後院 2、菜園・干し場進入 2、木戶・三戶前門・002 後門 5）：ON 0 FAIL、OFF 0 FAIL；接地喪失 0、卡住 0 |
| NPC 路徑 | 試點 rect 內 NPC 巡回路 0 條，M8 對 NPC 的檢查為空集合（不是「已驗證」） |
| 封存物 | 現行 seal 30 檔 1155／1155 一致；試點檔案不在任何 frozen 表 |
| 效能（**PRELIMINARY**） | ON−OFF 三鏡位：ΔGPU +0.32／−0.00／+0.07 ms、Δframe +0.05／−0.12／+0.26 ms、Δdraw +233／+189／+216、Δobjects +282／+234／+264；ON 時 GPU 9.3–11.0 ms。測量時使用者兩個 Blender 與瀏覽器開著（GPU 前檢 2–5 %），未達 DCC 全關的條件 |
| LOD／可見距離 | 沿用 P3 bundle 設定，**未另行測切換行為** |

gate 歷程（`evidence/GATE_HISTORY.txt`）：校正輪 M12 浮空 4（實為站在無碰撞的店先帶）＋反向 7／8；r1 M10 嚴重縮短 5（002 後壁的笊棚、003 的材木）＋若杉浮空 1；r2 全過；r3 M10 嚴重縮短 18（新加的 002 側下屋）；r4 起全過。

## 5. 工作分工（實際發生的）

- **Blender MCP 完成**：載入唯讀參考（999 件）與資產庫；參考建物 AABB 比對；seed 33 件；29 件新配置與兩輪修正（移動、刪除、換資產、非均勻縮放）；即時檢查（道路、戶口、footprint 重疊、SpringArm 通道）；匯出 manifest（未變更時不重寫）；增量修改測試；存 `.blend`；高位構圖檢視。
- **仍需 Godot**：真實地形與可視地面高度、參考 context 匯出、bake 與接地、runtime AABB、三角形貫通、SpringArm、真玩家實走、TPS 拍攝、效能。
- **自動化**：context 匯出、bake（同 manifest＋同 bake 規則時不重寫 `.scn`）、14 項 gate＋8 反向案例、`--baseline` 只驗改動項、實走／拍攝／效能 harness、比較圖與畫面占比（ID pass）。

## 6. 問題與未解決

已處理：
1. M12 原本只看 TerrainCollision，把站在無碰撞店先帶／院子上的物件誤判浮空 → 改為同時認可 `W9.top_h` 的可視支撐面並另列；浮空容差 0.05 m 未動。
2. 實走腳本把折線巷道當直線，ON／OFF 都在 003 正面卡住（腳本錯，不是試點） → 改為沿巷折線分段。
3. Godot 4.7 每次 bake 都給節點新 unique_id，同輸入 `.scn` byte 也會變 → `district_build.gd` 比對 overlay 內 `manifest_sha256`＋`bake_version`，相同則不重寫（`--force` 可強制）；第二次 build 實測 hash 不變。
4. 002 側壁下屋造成 SpringArm 嚴重縮短 18 處 → 改為貼壁薪堆；002 後壁笊棚同理移除。
5. r4 版面實走 ON：`hoshiba_in`（進干し場）在離終點 1.22 m 處卡住（OFF 通過＝試點造成）→ r5 把俵移離步道終點、藁塚換成藁束；r5 實走 ON 15 腳 0 FAIL（`evidence/walk_ON_r4_fail.json` 留存）。

**未解決（送審）**：
- 美術：V1 巷口分岔仍空；V3 後院道具像佈景（柴垣片段、容器、凳子散置）；V4 住宅列裏側直立物件用途不明；vision 指出一個白色鐘形大籠比例搶眼（對應物件待審圖時確認）。AI vision 評分 P8／PILOT：V1 1／2、V2 3／3、V3 3／3、V4 2／2、V5 3／3。
- 效能數據為 PRELIMINARY，需在 DCC 全關時重測。
- LOD 切換、NPC（範圍內無巡回路）未驗。
- 平面圖目視有幾處足跡貼近道路邊與 003 戶口標記；gate 實測觸碰 0，但建議審圖時看 `review/B8P_plan_map.png` 確認。

## 7. 對後續街區的建議

- **可取代 Godot 逐件 planner 作為施工方式**：一次看到整條街、單件改動 0.07 s 回饋、Godot 端 ~23 s 增量驗證；工程規則全部保留在 Godot gate。
- **不改變的**：manifest 是唯一權威；`.blend` 是工作檔（可由 context＋manifest 重建）；Godot 保有接地、碰撞、驗證與最終掛載。
- **規模**：62 件＋參考 999 件在同一個 Blender session 中，單件改＋檢查＋匯出 0.07 s；整村 187 棟不必載入，以街區 rect＋周邊參考即可。較大街區（150–300 件）主要成本會在 SpringArm 與實走 harness 的腳本化路段，需先在 context 定好通行帶。
- **下一個建議遷移**：A8 稗田邸西接近路（P8 已有 seed、地形單純、無封存衝突）。若要測規模，再選主街中段一個街區。
- **需要使用者裁定**：B8P 是否取代 B8（兩者同範圍採 supersedes，不可同時掛載）；是否要先補一批「用出來」的生活資產（晾衣竿＋衣物、工作中的農具、炊煙）再擴大遷移。
