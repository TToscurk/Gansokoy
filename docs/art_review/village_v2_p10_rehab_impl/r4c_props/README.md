# P10 R4c — 稲架穿插修正＋A2 可讀性 Pilot（ART_REVIEW・未核准）

使用者 2026-10-09 D9：**R4c st_hasa LIMITED REPAIR**——修正竹竿、稲束幾何穿插；A2 只調必要位置；相關封存只在最終驗證及 ART_APPROVED 後重新封存。

## 根因（MASTER AUDIT R4c-01／02）
- `build_street_kit.py` hasa()：稲束兩半頂端圓心離竿軸 0.03 m < 束半徑 0.06＋竿 0.025 → **竿穿過稲束約 5 cm**；上段穗端 y 1.12 碰下段束頭；X 脚斜穿中央束列。使用處 9（R4 PilotA A1 2、R4b XA3 3、R2 FarmEdge 4）。
- A2 脫穀作業床：背負い籠擋在農道機位與千歯扱き之間（千歯扱き 2/1 的主因）。

## 做法
- **新資產 `st_hasa_v2`**（不覆寫封存的 street_kit）：`assets/blender/village_v2/build_hasa_v2.py`（Blender 5.2.1，沿用 v2_kit 與 street_kit atlas）→
  `assets/village_v2/r4c_kit/src/r4c_kit.glb`＋基本體規格 `hasa_v2_spec.json` → `verify_village_v2_prop_fix.gd --convert` → `maps/village_v2/gen/r4c/st_hasa_v2(_l1).res`（材質＝V2_Wood／ST_Street）。
  - 稲束「跨竿」：束頭（結び）是一段橫跨竿頂的短束、坐在竿上；兩半從竿兩側外掛（與竿淨距 ≥ 0.012 m），穗端外開朝下
  - 上段束長 0.36–0.42（穗端離下段束頭 ≥ 0.03 m）；X 脚位置不變，束列避開脚（上段 ≥ 0.22、下段 ≥ 0.36 m）
  - 外形尺寸＝原 st_hasa（AABB 相同）→ 原擺放直接換；1424／584 三角（LOD0／LOD1）
- overlay `PropFixP10`（ShrineApproachP10 之後）：執行期把全村 st_hasa／_l1 的 mesh 換成 v2（位置／件數不動）；A2 背負い籠東移 1.0 m（只動這一件）。

## 審圖（Agent 自評，vision，非 ART 判定）
- 稲架近距 `r4c_hasa_A1_close` 4/5（穿插 0；束頭偏方、稲穂質感不足）、10 m `r4c_hasa_A1_10m` 4/5（略像柵）
- A2 `r4c_dakkoku_A2`（MASTER AUDIT 同機位）**4/5**（r1b 接地修正後重拍；r1 的圖籠子沈在地下＝3/5）：千歯扱き的框架露出來了；齒在此距離仍讀不清、籠子仍貼著筵前緣
- 1 輪（無迭代）：本輪只做 D9 授權的幾何修正與 A2 單件移位，不加道具

## r1b 技術修正（全回歸で発覚した不具合）
- **A2 背負い籠が地面に 1.0 m 沈んでいた**：r1 の gate は移位後の高さを「原位置の地面」との差で決めていたが、原位置の射線が籠自身の碰撞（高 1.0 m）に当たっていた → 新位置で 1.0 m 沈む。
  全回歸の HUSE「擺放（接地）最大の埋まり 1.002 m」で発覚。→ 地面＝P1 TerrainCollision だけを認める射線に修正（新位置の籠底 −0.002 m＝原位置と同じ）、
  plan gate に「移位後も接地（|·| ≤ 0.15）」と反向 **N5「籠が 1.0 m 沈む」→ FAIL** を追加、scene gate にも移位後の接地を追加。

## 驗證
- plan＋反向（`gate_plan_negatives.log`）：竿×半束 0.016 m（≥ 0.010）、束頭坐竿上 0.001 m（接觸不穿）、束×束 0.011 m、脚×束 0.063 m、網格＝manifest／同尺度；
  A2 視線（農道→千歯扱き）距籠由原本 < 0.45 m 增加到 ≥ 0.45、落地、不撞；反向 5（舊束形、上段過長、束掛脚上、籠不動、籠沈む）全部正確 FAIL。
- scene（`gate_scene.log`）：換 mesh 的 MeshInstance 數＝overlay 計數、殘留舊 mesh 0、A2 移位 1 件＋移位後接地、開關還原。
- 封存：R2／R4／R4b seal **不重封**（D9：ART_APPROVED 後才併入 street_kit 並 reseal）；pilot 期間 `--seal` 照舊（overlay 只在執行期換 mesh／移位）。
