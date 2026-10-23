# Blender 資產檢查表（人間之里 V2）

> 狀態：`CHECKLIST v0.1`（2026-09-23）。依據：V2 全面重製計畫 §13–22、§26、§41–43、§47–49、§51。
> 機器可判定的項目由 `godot/tools/qa_assets_v2.gd` 自動檢查；其餘要在 Blender 裡人工確認。
> 通過本表 ≠ 美術核可。美術最多給到 `ART_REVIEW`，`ART_APPROVED` 只有使用者能給。

## 0. 流程（§13、§22、§49）

```text
Import → Inspect → Measure → AABB → Geometry Audit → Bottom Audit → Separate
→ Cleanup → Materials → LOD → Collision → Export → Godot Verification（qa_assets_v2.gd）
```

- Tripo／Meshy 等 AI 產出一律當 **Raw Asset**，不能直接進地圖。禁止「Import → Export」直通。
- `godot/assets/blender/sources/` **全程唯讀**（專案紅線 3）：只從這裡讀，產出寫到別處。
- 匯出沿用 `godot/assets/blender/` 既有腳本的匯出呼叫，不另外建匯出流程。

## 1. 尺度、方向、Transform（§4、§20）

- [ ] 以**真實公尺**建模並匯出（Scene Unit Scale = 1.0）。一般町家約 8 × 6 × 6 m，不是 1 m 方塊。
- [ ] 正面朝 **Blender −Y**（按 Numpad 1 的 Front 視圖看得到的那一面）。
      實測：Blender 裡 (0, −3, 1) 的物件匯出後在 glTF／Godot 是 (0, 1, 3)，所以 Blender −Y 就是 Godot **+Z**。
- [ ] 匯出前 Apply All Transforms：`bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)`。
      Rotation 要是 0、Scale 要是 1。
- [ ] Godot 放置時 Scale 維持 (1, 1, 1)，只接受小幅調整。不可以用 0.37、2.8 這種極端或非均勻的縮放去補救模型。

## 2. 原點（§19）

| 類別 | 原點 |
|---|---|
| 建築 | 底部中心（地基底面，Y = 0） |
| 樹 | 樹幹與地面接觸的中心 |
| 石 | 底部中心或質量中心附近 |
| 橋 | 照模組擺放規格（**尚未訂**，P3 水系階段一起訂） |

禁止：原點離模型幾十公尺、原點在世界原點而不在資產上、原點在屋頂、原點在無關的土塊上。

## 3. 底部與側向污染（§15–18）

- [ ] 建築**不帶土塊**：`Building / Foundation / Optional Ground Detail` 分件。
- [ ] 一般樹只允許 `Trunk / Roots / Branches / Leaves`，不能附一大坨土台。
      英雄景觀才可以另做 `Tree_Hero_GroundCluster`，而且不能拿來當一般 scatter 樹。
- [ ] 底部容差：樹 −0.1 到 −0.3 m；建築依地基規格。底部 −3.8 m 的普通町家要標 `ASSET_BOTTOM_CONTAMINATION`。
- [ ] AABB 的 X／Z 要跟視覺尺寸一致。8 m 的房子 AABB 卻有 28 × 7 × 30 m，代表有 stray vertex、隱藏物件或殘留幾何，不能進正式場景。

## 4. 拆件（§14）

重要建築不可以焊成一整塊，至少拆成：

```text
Building_Main  Foundation  Roof  Doors  Windows  Engawa  Stairs  Signs  Curtains  Fence  Props
```

大型建築可以再拆：`Wall_A / Wall_B / Roof_A / Roof_B / Interior / Exterior`。
拆開後才能個別換材質、換門窗、做損壞版、做 LOD、調地基，不用整棟重生。

## 5. Mesh 缺陷（§21）

以下運算子已在 Blender 5.2.1 確認存在：

| 檢查 | Blender 操作 |
|---|---|
| non-manifold | `bpy.ops.mesh.select_non_manifold()` |
| 重複頂點 | `bpy.ops.mesh.remove_doubles()`（Merge by Distance） |
| 翻面 | `bpy.ops.mesh.normals_make_consistent()`，另外用 Face Orientation 目視 |
| 浮空／孤立幾何 | `bpy.ops.mesh.delete_loose()` |
| 零面積面 | `bpy.ops.mesh.dissolve_degenerate()` |
| 內部面 | `bpy.ops.mesh.select_interior_faces()` |
| 拆件 | `bpy.ops.mesh.separate()` |

AI 資產常見：屋頂跟牆焊在一起、門窗其實是一坨面、屋內有肉塊、背面多出結構、底下形成巨大封閉 mesh。這些都要修。

## 6. 材質（§26）

- [ ] 主要材質至少考慮 Base Color、Normal、Roughness、AO。
- [ ] 避免：完全平滑的木頭、所有瓦片一樣反光、像塑膠的土地、像水泥球的石頭、全部材質同一個 roughness。
- [ ] 木構要有年代感、色差、紋理方向、roughness 變化。
- [ ] 每個 surface 都要有材質（沒有會被 QA 標 `NO_MATERIAL`）。

## 7. 面數與 LOD（§41、§43）

- 重要模型要有 LOD0（近）、LOD1（中）、LOD2（遠），可再加 LOD3／Impostor。不可以讓百萬面的房子在 150 m 外還全量渲染。
- Godot 匯入已開 `meshes/generate_lods=true`（`assets/machiya/町家.glb.import` 已確認）。
  但如果連最低一級自動 LOD 都還超出預算（`HIGHPOLY_NO_USABLE_LOD`），就要回 Blender 用 Decimate modifier 減面，或手做 LOD。
- QA 工具目前的面數門檻如下。這些是**工具暫定值，還沒經過使用者核准**，要跟「可見面數 ≤ 600 萬」這項決策一起裁定：

| 類別 | 最大邊合理範圍 | 底部容差 | 三角面門檻 |
|---|---|---|---|
| building | 3–40 m | −0.5 m | 150,000 |
| landmark | 3–60 m | −1.0 m | 300,000 |
| tree | 2–40 m | −0.3 m | 30,000 |
| rock | 0.1–15 m | −0.5 m | 8,000 |
| prop | 0.05–8 m | −0.1 m | 10,000 |
| bridge | 2–60 m | −3.0 m | 60,000 |

## 8. Collision（§42）

- [ ] 重要高模不可以只靠 `Create Trimesh Collision`。建築用 Box、Convex 或簡化 mesh；樹通常用 Capsule 或 Cylinder。
- [ ] 在 Blender 裡另做低面數的碰撞代理，用 Godot 匯入後綴命名（依官方文件 *Node type customization*）：
  - `名稱-colonly`：匯入時移除這個 mesh，改成 StaticBody3D 碰撞（凹多邊形）。
  - `名稱-convcolonly`：同上，但用凸分解。
  - `-col`／`-convcol`：保留原 mesh，再附加碰撞。**不要用在高模上**。
  - 官方建議：盡量用少數幾個基本形狀。用 Blender Empty 當碰撞形狀的做法只適用 Collada，GLB 不適用。

## 9. Godot 驗證（§16–18、§47–48）

```text
D:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/qa_assets_v2.gd -- [--cat=building] <res://路徑…>
```

- 報表會寫到 `docs/art_review/asset_qa/qa_<時間>.csv`。拿到 `QA_PASS` 才能擺進 V2；`QA_FAILED` 目前只記錄、**禁止搬入正式 V2**，依 2026-09-23 裁示不做批次修復。
- §47 QA 表欄位的來源：

| 欄位 | 來源 |
|---|---|
| Dimensions、AABB、Triangle Count、Material Count、Node Count、Bottom Y、LOD 數、Pivot 判定、底部與側向污染 | `qa_assets_v2.gd` 自動產生 |
| Normals、non-manifold、隱藏幾何 | Blender 人工確認（第 5 節） |
| Collision 類型 | 人工確認（第 8 節） |
| Approved | 只有使用者能給（`ART_APPROVED`） |

## 10. 現況基線（2026-09-23，`qa_20260923T192058.csv`）

V2 候選清單共 31 件：**29 件 `QA_FAILED`、1 件 `QA_WARN`（霧雨店，只超面數）、1 件 `QA_PASS`（竹垣）**。`QA_FAILED` 的 29 件只記錄，禁止搬入正式 V2，本階段不修。

| 旗標 | 件數 | 代表什麼 |
|---|---|---|
| `SCALE_SUSPECT` | 28 | 最大邊只有約 1–2 m（Tripo／Meshy 的正規化尺寸），進場景後靠 scale 放大，違反第 1 節 |
| `TRI_BUDGET` | 13 | 建築 28–104 萬面（寺子屋約 104 萬） |
| `PIVOT_CENTERED` | 12 | 原點在半高，擺到地面會埋一半 |
| `HIGHPOLY_NO_USABLE_LOD` | 7 | 最低一級自動 LOD 仍超預算 |
| `BASE_SLAB` | 6 | 樹自帶土台（2大衫、普通樹、松樹、楓樹、櫻花樹、針葉林樹4） |
| `FLOATING_PIVOT` | 2 | 農舍、龍神像：底部高於原點，擺到地面會浮空 |

結論：現有町家、樹、地標資產**都不能直接搬進 V2**，要先照本表在 Blender 修尺度、原點、土台與面數。
