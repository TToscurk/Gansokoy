# 丘腳社寺 境內環境（TASK E2）驗收報告

**狀態：ART_REVIEW（等使用者裁定；Agent 不自行 ART_APPROVED）。** 未宣告任何全域 CONTENT_FREEZE。
社寺本體與其碰撞未動（`LANDMARK_HILLFOOT_TEMPLE` origin (228.000, 1.198, −170.000)、yaw 0°，`village_v2.tscn` 對 HEAD 僅 +6 行掛載）。

## 1. 做了什麼

在 `village_v2.tscn` 根下加兩個節點（`DevLayerGate` 之前）：

| 節點 | 來源 | 內容 |
|---|---|---|
| `HillfootPrecinctE2` | `gen/hillfoot_precinct_e2.scn` | `Ground`（既有 `sg_ground` 材質的地面網格，4362 三角形）＋可逆抑制腳本 `hillfoot_precinct_e2.gd`（`@tool`，`enabled` 開關） |
| `DistrictHF` | `gen/district_hf.scn` | 街區管線 **HF**：60 件（Blender 配置 → `HF.json` → Godot），全為既有資產 |

**沒有新 shader、新材質檔、新模型。** 只在材質實例上調 `gravel_tint`／`gravel_contrast` 兩個既有 uniform。
**還原**：`HillfootPrecinctE2.enabled = false`（E082 垣・草株・新植栽・地面一次回到 BEFORE），或 `python godot/tools/p13/w9/e2/mount_hf_precinct.py --detach`（拆掉那 6 行）。

### 現場量測（`evidence/survey_site.txt`、`terrain_1m.csv`、`terrain_profiles.txt`）
- 整地面平坦於 y 1.198（x 219–237、z −179…−161）；石段腳約 (228, −165)；丘腳街南緣 z≈−152.1（路面比地形高 +0.099）。
- 街→整地面之間有 0.57 m 的落差（z −153.5 的 y 1.718 → z −157 的 y 1.145 ≈ 9°），再爬回平台：這是參道的真實高低，**沒有改地形**。
- 西側有水溝肩（x≈215–218）、東／北為丘腳坡。保留區 18×12 並不是境內邊界；實際境內多邊形由量測決定（`data/district/HF_design.json`）。

### 地面與配置
- **地面**：前庭（皿狀窪地到平台）＋後院＋參道（街→石段腳，寬 3.0→1.6→3.8 m 的收放，邊緣雜訊）＋兩側踏跡；組成＝踏實土為主、石段前細礫斑（3 塊，雜訊崩邊）、北側少量苔、林緣落葉；邊緣以 shader 的 dither 淡出，不是矩形板。
  高度＝可見地形＋0.032 m（既有重疊層 ≤ +0.019），三角形內部取樣上抬；地形凸部（> 6.5 cm）的頂點被覆率漸隱到 0（68 頂點），不在凸岩上蓋地面。
- **踏石・小石**：共 12 顆（`gk_tobi_*` 9＋`gk_kei_flat` 3）：參道與石段前 5 顆（窪地坡段 z −153…−160 只有 1 顆）、前庭／後院 7 顆；只放在足下高低差 ≤ 3 cm 處。
- **植栽（境界）**：羊歯 12・笹 9・低木 9・躑躅 6・若杉 3・若い広葉樹 3・黒松 1・景石（低）5，集中在外緣（西南窪地、西縁、後方杜、東縁、東南角）；前庭與參道廊下不放。

## 2. 被移除／抑制的原有物件（全部可逆，原檔一個位元組都沒改）

**EnvironmentP9 `edge/E082_fence_frag`（7 件，visible=false）＋ `EnvironmentP9/Collision` 同名 `_c` 5 個碰撞（disabled）**

| 節點 | 位置 (x, y, z) |
|---|---|
| 443_gk_yotsume（四目垣）| (229.70, 1.20, −162.69) |
| 444_gk_yotsume（四目垣）| (227.66, 1.20, −161.82) |
| 445_rb_pile_r（瓦礫堆）| (226.95, 1.12, −161.80) |
| 446_rb_pile_a（瓦礫堆）| (224.66, 1.03, −160.84) |
| 447_shrub_a（低木，無碰撞）| (218.97, 0.78, −161.88) |
| 448_rb_bld_d（瓦礫）| (217.35, 0.65, −162.20) |
| 449_shrub_a（低木，無碰撞）| (222.86, 0.94, −160.08) |

**MeadowP9／GroundcoverP9 的 MultiMesh 草株：境內多邊形（＋0.4 m）內 302 個實例（23 個 MultiMesh 節點，逐節點見 `evidence/verify/mm_trim_breakdown.txt`），占全場 177,570 個的 0.17%。** 做法＝複製該 MultiMesh、把這些實例沉 0.30 m 並縮 0.001（行列式 ≠ 0）；原 MultiMesh 資源由 `_restore` 換回，存檔前（`NOTIFICATION_EDITOR_PRE_SAVE`）自動還原，所以 `village_v2.tscn` 不會被寫入抑制狀態。

其他 EnvironmentP9 物件、鄰近建物、既有路徑一律未碰。

## 3. 驗證結果（全部為本輪實際執行的輸出；`evidence/verify/`、`evidence/walk/`）

### 3.1 `verify_hf_precinct.gd`（非 headless；14 項 PASS／0 FAIL）
| 項 | 結果 |
|---|---|
| M1 掛載＋抑制 | E082 7 件全不可見，5 個碰撞全停用 |
| M2 可逆 | 關閉：E082 7/7 可見、碰撞 5/5 啟用、境內草株 302/302 回來、DistrictHF／Ground 隱藏；開關往返×3 一致 |
| M3 草株 | 抑制中境內可見草株 0（抑制前 302）；全場零矩陣實例 0／177,570 |
| M4 編輯器存檔語意 | PRE_SAVE 全部還原（E082 7/7、碰撞 5/5、草株 302），POST_SAVE 再抑制（可見 0） |
| G1 地面 vs 地形碰撞 | 頂點差 min 0.032、可走區 p95 0.032、可走區最大 0.069 m |
| G2 不潛入地形 | 三角形內 7 點取樣，Ground − 可見地形 最小 +0.014 m（門檻 ≥ 0.012） |
| G3 Z-fight | 與 95 個候選面層垂直差 < 8 mm 的點 0；最小差 +0.009（Groundcover MV_9_-7）|
| G4 無縫隙 | 開放邊界頂點 580，被覆 > 3% 且不在台基箱／街接縫帶 0；Ground 無碰撞體 |
| P1 石段與台基 | 與石段稜柱／社殿碰撞最小間隙 0.76 m（黒松 HF_0018）；無物件中心落入 shrine_box |
| P2 入口不被擋 | 參道 13.3 m，膠囊 r0.35（中心＋側向 ±0.8）162 次查詢，碰撞命中 0 |
| P3 無隱形碰撞 | DistrictHF 6 個碰撞形狀都有對應可見網格；Ground 無碰撞 |
| P4 石頭座落 | 12 顆：石頂 − 地面 0.054–0.248 m（門檻 0.012–0.25；全部外露、無埋沒） |
| P5 社寺不動 | origin (228.000, 1.198, −170.000)、yaw 0°、碰撞形狀 8（與 HEAD 同） |

### 3.2 既有管線與回歸
- `district_verify.gd --district=HF`：**PASS 14／FAIL 0**；反向 7 OK／**1 BAD**（「道路の上へ移動」反向在 HF 矩形內找不到道路折線頂點，無法執行；B8P 可。這是反向測試的覆蓋限制，不是配置缺陷）。M5b runtime AABB 差 ≤ 0.0003 m；M6 配置 60/60 合法；M10 通行帶 9,920 樣本，**碰撞造成的 SpringArm 重縮 0 件**（最差 5.83→4.97 m）；M11 預算 LOD0 28,798 三角形／MeshInstance 170／碰撞 6／MultiMesh 0。M12 REVIEW 26 件（坡上灌木／岩石半埋，最大埋入 1.04 m＝東北坡上的 `gk_kei_low` HF_0059）——管線標記為「請目視」，非 FAIL。
- `MMBAKE`（`verify_village_v2_multimesh_bake.gd`，非 headless）：0 項失敗。
- `verify_editor_tool_overlays.gd`：15 通過／0 失敗。

### 3.3 真玩家控制器實走（`evidence/walk/PREC_walk.json`；`repro/walk_precinct.gd`）
| 路線 | 結果 |
|---|---|
| A 街→參道直走→石段→頂 | 到石段頂，在 `Hero/Collision`（社殿正面）停住（與上輪相同的既有行為）；無浮空、單幀最大垂直變化 0.047 m |
| A2／A3 西／東斜進參道 | reached、無卡住、max_dy 0.048／0.030 |
| S 踏石串走 | reached、無卡住、max_dy 0.031 |
| B 下石段、C／C2 前庭橫走、D 繞社殿一周 | 全 reached、無卡住、lost_floor 0 |

**石段腳高差（既有已知問題）**：腳底 − 可見石段面 min 0.087／max 0.307／mean 0.270 m；上輪（社寺掛載）為 0.082／0.301／0.268——**未增加**（石段碰撞與石段網格都沒動；差 ≤ 6 mm 來自行走路徑不同）。

**SpringArm**（境內 18 點×8 方位＝144 樣本，同一次執行內切換 `enabled` 取 BEFORE）：最短 AFTER 0.78 m／BEFORE 0.78 m（同一個既有位置）；< 2.0 m 的樣本 AFTER 9／BEFORE 9；比 BEFORE 短 > 0.25 m 的只有 1 個（4.99→4.70 m，仍未壓縮）。→ **無新增重度壓縮。**

## 4. 前後對照（同一世界座標相機、10:00、Forward+；`review/`）

| # | 視角 | 檔案 |
|---|---|---|
| 1 | 丘腳街接近 | `review/cmp_v1_street_approach.jpg` |
| 2 | 17 m 入口 | `review/cmp_v2_entrance_17m.jpg` |
| 3 | 正面整個前庭＋石段 | `review/cmp_v3_front_courtyard.jpg` |
| 4 | 石段頂望向村落（**實際 TPS 相機**，玩家站在石段頂）| `review/cmp_v4_stairtop_to_village.jpg` |
| 5 | 俯視整個境內 | `review/cmp_v5_elevated_precinct.jpg` |
| 6 | 側面（西／東）過渡 | `review/cmp_v6_side_west.jpg`、`cmp_v6b_side_east.jpg` |
| 診斷 | 正射俯視（非美術證據）| `review/cmp_d_ortho_top.jpg` |

- BEFORE 原件拍於掛載前；為證明「可逆＝原狀」，另用 `enabled=false` 重拍 3 視角：環境區域與原件無差異（差異集中在玩家姿勢處；兩次 toggled 之間的雜訊底為 v3 1.2%／v2 3.1%／ortho 0.09%）。v4 因第一版自由相機鑽進玩家頭髮（BEFORE／AFTER 皆無效），已改為實際 TPS 相機重拍，BEFORE 以 `enabled=false` 取得。
- 我（Agent）的目視讀法，**僅供參考、不是驗收**：
  - 達成：四目垣與孤立木樁消失、石段正面全開；前庭不再是草坪（踏實土＋細礫斑＋小石）；外緣植栽收邊，前庭中央無植栽。
  - 仍不足（請你裁定）：
    1. 細礫斑偏灰冷，與周圍暖褐土之間有一條可見色差帶。
    2. 石頭沒有接觸陰影／埋入感（kit 石＋地面是兩個物件）；前庭的平石 `gk_kei_flat`（3 顆，最近一顆在石段腳前 2.7 m）約 1.4×1.0 m，比「疏小石」大。
    3. 前庭邊緣仍有零星草斑（地形本身的草＋境內多邊形外的 Groundcover）。
    4. v1 街上視角：街邊的低木帶把參道下段部分遮住（物理上通暢，P2 通過）。
    5. 參道踏石偏少：9° 的窪地坡段因「足下高低差 ≤ 3 cm」規則只放了 1 顆。

## 5. 視覺迭代次數（如實揭露）
任務規定初版後最多 2 輪聚焦修正。實際：初版 r1 → 修正 r1b（地面組成、邊緣）→ 修正 r2（石頭、礫斑配色）→ **第 3 輪 r3（超出 1 輪）**。第 3 輪不是美術調整，而是驗證腳本實測出的缺陷：踏石有 3–4 顆埋在 Ground 下（P4）、Ground 開放邊界有殘留被覆（G4）、東側樹幹碰撞使 SpringArm 重縮 7.50→1.85 m（M10）。之後只做這些缺陷的修復與 v4 相機重拍，沒有再做美術取向的調整。

## 6. 已知限制
- 見 4. 的 5 點。細礫色差與石頭接地感若要再修，建議先決定礫斑配色（暖化）與是否給 kit 石加接觸暗化，不在本輪範圍。
- 可見地面比地形碰撞高 3.2 cm（可走區最大 6.9 cm）：腳會陷進可見面 3 cm 左右；既有重疊層為 ≤ 1.9 cm，這裡多 1.3 cm（為了避開與 Groundcover 的 Z-fight，G3 最小差 +9 mm）。
- 抑制的草株是「沉下並縮小」而非移除，GPU 仍會繪製 302 個退化實例（可忽略）。
- `village_v2.tscn` 是 gen_village_v2.gd 產出（TYPE B）：重新產生後要再跑 `mount_hf_precinct.py --attach`。
- 新增腳本沒有 `.uid`（Godot 編輯器掃描時會自動產生）；效能（幀時間）本輪未量；實體編輯器 UI 未操作（編輯器存檔語意以 `NOTIFICATION_EDITOR_PRE/POST_SAVE` 在腳本中模擬驗證）。
- 反向測試「道路の上へ移動」對 HF 無法執行（見 3.2）。

## 7. 檔案清單
**修改（5）**：`godot/maps/village_v2/village_v2.tscn`（+6 行掛載）、`godot/tools/district/district_{lib,build,context,verify}.gd`（HF 街區表項、`suppress`＋`prepare_scene`、`surface`＋`attach_surface`／`top_h`／`ground_y` 包裝；對其他街區行為不變）。
**新增（godot/）**：`data/district/HF_design.json`（單一幾何來源）、`data/district/HF.json`（manifest 60 件）、`maps/village_v2/gen/{district_hf,hillfoot_precinct_e2}.scn`、`maps/village_v2/scripts_p13/hillfoot_precinct_e2.gd`、`tests/district/district_hf_test.tscn`、`tools/p13/w9/e2/{hf_precinct_lib.gd,build_hf_precinct.gd,hf_blender_place.py,verify_hf_precinct.gd,mount_hf_precinct.py}`。
**新增（docs/）**：本報告、`review/`（8 張對照）、`evidence/`（勘查腳本與輸出、`repro/` 重現腳本、`verify/`、`walk/`）。`shots/` 被 `.gitignore` 排除（本機有全部原圖）。
**不在版控**：`work/district/HF/`（Blender 工作檔，被 `.gitignore` 排除）。

重建順序：`build_hf_precinct.gd` → `district_context.gd --district=HF` → `blender -b --factory-startup --python hf_blender_place.py`（隔離背景實例，沒碰 GUI Blender／9876 埠）→ `district_build.gd --district=HF` → `mount_hf_precinct.py --attach`。

## 8. Git 所有權檢查（commit 前）
- 開工快照（`HEAD c573df6`、暫存 53 件）對現況：暫存集合與 `git diff --cached --raw` 雜湊**完全相同**（本輪未動暫存區）。
- 開工後新增的追蹤檔變更只有上列 5 件修改；`git diff` 內容全為本輪行。
- **不屬本輪、未納入**：`godot/assets/village_v2/hillfoot_temple/gate.json`（開工前已是 modified，22:39 前的社寺 gate 重跑）、`godot/tools/yoriichi_r61/capture_r61.gd`（本輪進行中由別的 session 寫入）、其餘既有的 10k+ 未追蹤檔。
- 提交只含本輪檔案（`git commit -- <路徑>`），不 push。
