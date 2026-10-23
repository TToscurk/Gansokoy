# TASK E FINAL：丘腳社寺撤除 → 自然林（ART_REVIEW，未批准）

> 使用者 2026-10-18：社寺取消，原境內改為與丘腳林相連的自然林。本輪是撤除與復原，不是新美術階段。
> **狀態：ART_REVIEW。** 沒有宣告 CONTENT_FREEZE，沒有 push、沒有 commit。

## 1. 改了什麼

| 項目 | 做法 |
|---|---|
| 社寺本體 | `village_v2.tscn` 拿掉 `Landmarks/LANDMARK_HILLFOOT_TEMPLE/Hero` 實例與其 ext_resource，共 −5 行／+1 行（`evidence/scene_diff.txt`）。anchor 留成空的 Node3D，掛 `metadata/cancelled`。理由：`layout_v2.json` 封存不改，其他 gate 仍要讀地標座標。工具：`mount_hillfoot_temple.py --cancel`；重生村落後要再跑一次，Hero 與 P0 灰盒 Block 都會移除。 |
| 灰盒不再出現 | `tools/build_village_v2_asset_registry.py` 加 `CANCELLED`：`hillfoot_temple` 改列 `v2_rejected`，不再登記 `v2_assets`。產生器 `_heroes()` 只放已登記的資產，所以重生後也不會放回社寺。灰盒 Block 由 `--cancel` 移除。資產檔 `assets/village_v2/hillfoot_temple/`（GLB、來源、LOD）**原樣保留**。 |
| E2 境內 | `HillfootPrecinctE2` 重烘：拿掉 Ground（細礫／踏實土地面），`mm_polys` 清空，原境內 557 株草全部恢復。保留可逆抑制 E082 四目垣斷片（7 件、碰撞 5 個），避免舊垣回到林裡。節點名、掛載行沿用 E2，`village_v2.tscn` 的掛載不變。 |
| DistrictHF | 同一條街區管線（Blender 背景配置 → `HF.json` → bake）重排為自然林：74 件既有資產，大樹 19、若木 11、下層 41、林床景石 3。不含踏石、燈籠、鳥居、垣、參道。不新增 mesh 或材質。 |

林的配置（`HF_design.json`）：
- 不規則多邊形林區，南緣距丘腳街北緣 ≥ 3.3 m。
- 14 個大小、樹種不一的群落：櫸、椎、小楢、赤松、榎、若杉、若い広葉樹。
- 2 個小空地，刻意避開原中軸 x≈228。
- 原社殿位置用大樹群填滿。

## 2. 驗證（本輪實際執行；`evidence/`）

| 檢查 | 結果 |
|---|---|
| `verify_hf_precinct.gd`（改寫為林地版，非 headless，正式 main.tscn＋實際 TPS） | **8／8 PASS**（`HFW_verify.json`、`HFW_run.log`） |
| W1 社寺不在 | anchor 子節點 0；runtime 中來自 hillfoot_temple.scn 的節點 0；`village_v2.tscn` 依存 0；原 footprint 內 Landmarks 碰撞體 0（灰盒沒有出現） |
| W2 隱形碰撞 | 球查詢 8,967 次（地面上 0.5／1.2／1.9 m）：命中 16 個碰撞體，全是 DistrictHF 樹幹／石，每個都對得到可見網格；無主碰撞 0 |
| W3／W4 | E082 7 件不可見、碰撞 5 個停用；草株 557／557 可見；全場零矩陣 0／177,570 |
| W5 可逆 | `enabled=false` 時林隱藏、碰撞 22／22 停用、E082 回來；切回後一致；PRE_SAVE／POST_SAVE 一致 |
| W6 道路 | 丘腳街膠囊 558 次，碰到林木碰撞 0。樹幹到路肩最小距離：大樹 9.21、若木 7.15、下層 4.63 m |
| W7 自然度 | 樹 30 株：最近鄰距離 CV 0.28、樹高 4.2–17.8 m。第一版 CV 0.19 不及格，處理方式是重排配置（加群落、群內幹距拉近），**沒有放寬門檻** |
| `district_verify.gd --district=HF` | **PASS 14／FAIL 0**（詳見下方） |
| MMBAKE（非 headless） | 0 失敗 |
| ENV scene（EnvironmentP9） | 0 失敗 |
| EDTOOL | 15／0 |
| 其他回歸 | GB 0、PARCEL 0、SL（視線）0；FREEZE 0、PROTECT 0、HERO 0；WALK 19／19，最大高低差 0.07 m |
| 換圖（`smoke_portal_transitions.log`） | 實走 portal：V2 → 獸道 → V2 OK；load_map 6 條：beast_path／hieda1f／kourindou 往返全部落地，落點與 W9 收尾 `smoke_disk.json` 相同 |

`district_verify` 細項：
- M5b runtime AABB 差 ≤ 0.0008 m；M6 配置 74／74 合法；M7 實際貫穿 0。
- M10 丘腳街 SpringArm 被林木碰撞明顯壓縮 0 件。
- M11 LOD0 118,096 三角形 ≤ 200k。
- M12 接地 524 條射線：浮空 0、最低支持率 100%。

效能（同一 TPS 鏡位、1600×900、各 90 幀平均）：

| 鏡位 | 林（現況） | 社寺 Hero（記憶體內臨時掛回＝撤除前近似） |
|---|---|---|
| 街道 | 6.87M primitives／4,236 DC | 6.69M／4,166 |
| 原址 | 7.61M／3,894 | 7.37M／3,782 |
| 俯瞰 | 6.98M／5,499 | 6.80M／5,421 |

- 林比社寺多 +2.6～3.3 % primitives、+1.4～3.0 % draw calls。
- frame ms 受 vsync 限制，都是 16.5–16.8，量不出差別。
- 撤除前的 E2 地面與 60 件配置沒有算進「撤除前」，所以實際增量比表上更小。

## 3. 截圖（TPS，實際 SpringArm）

- `review/woodland_tps_3views.jpg`：①街道接近 ②原社寺位置 ③高處俯瞰（丘西肩 (214,−197)，相機約高出原址 10 m）。
- `review/woodland_diag_free_camera.jpg`：診斷用自由相機，斜俯與正俯，**不是美術證據**。正俯視圖上原址被樹冠蓋住，沒有空洞。

## 4. 仍存在的問題（請裁定）

1. **原址是平台地形**：產生器 pad 圓形整地，半徑 10.5 m，y 1.20。地面上看得出是一塊較平的裸土區，雖然已經不是矩形，也沒有空的中心。要真正消除得改地形：`layout_v2.json` 的 `pad` 加上重生地形，會碰到封存，本輪沒做。
2. **原址南側的灰色碎石斑**：來自封存的 GroundcoverP9 地被（`MacroVillage/MV_9_-7`），社寺之前就有，E2 時被地面蓋住。現在用下草部分遮住，沒有改封存層。
3. **TPS 俯瞰鏡位**：在林中，TPS 相機約一半畫面被近處樹冠擋住。已比較 15 個候選位置，這張是最好的；要看清全貌請參考診斷自由相機圖。
4. **既有、與本輪無關**：
   - ASSET 的 137 個 w9_kit 違規。
   - PLACE 的 22 個 REVIEW（NO_COLLISION_PROXY，市場／MXC／RSW 灰盒）：涵蓋單位 207 → 206，減少的那 1 個就是社寺；runner 對 PLACE 顯示 exit 127，手動重跑結果相同。
   - `district_verify` 反向案例「移到道路上」在 HF 範圍內找不到道路頂點，無法執行，與 E2 時相同。
   - `tools/p11r2/verify_p11r2_transition.gd` 是舊版工具（找 trail／hieda1f portal，但 V2 現在只有 beast_path portal），14／14 失敗與本輪無關；改用 W9 smoke 驗證換圖。
5. 工作區裡有兩個不是本輪改的檔案，**我沒有碰**：`hillfoot_temple/gate.json`（2026-10-17 22:39 的 gate 重跑）、`data/mapRegistry.json`（village → slice）。

## 5. 檔案

**修改：**
- `godot/maps/village_v2/village_v2.tscn`
- `godot/data/village_v2_asset_registry.json`（產生）
- `tools/build_village_v2_asset_registry.py`
- `godot/tools/p13/w9/mount_hillfoot_temple.py`（`--cancel`／`--check-cancelled`）
- `godot/data/district/HF_design.json`、`HF.json`
- `godot/maps/village_v2/gen/district_hf.scn`、`hillfoot_precinct_e2.scn`
- `godot/maps/village_v2/scripts_p13/hillfoot_precinct_e2.gd`（只改註解）
- `godot/tools/district/district_lib.gd`（HF 表：名稱、arm_lanes 改為丘腳街、拿掉 surface）
- `godot/tools/p13/w9/e2/{build_hf_precinct.gd, hf_blender_place.py, hf_precinct_lib.gd, verify_hf_precinct.gd}`

**新增：** 本資料夾（報告、`review/` 2 張、`evidence/`）。

**未動：** 資產庫 `hillfoot_temple/`、`layout_v2.json`、`godot/assets/blender/sources/`、其他建築、角色、portal、遊戲系統、所有封存 overlay。
