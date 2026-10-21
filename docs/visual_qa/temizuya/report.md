# Visual QA：temizuya

- 模式：full　profile：japanese_shrine　canon：None
- git c4be7e64（yoriichi-combat-and-village-routing）　2026-10-22 04:20:52
- Godot：4.7.2-stable (official)　renderer：forward_plus　GPU：NVIDIA GeForce GTX 1070
- 縮放：3.2　來源：shrine_v2：res://assets/shrine_v2/bld/temizuya.tscn（shrine_v2.tscn 節點 建築/手水舍 metadata/scale=3.2、aabb 3.19×2.64×2.90 m）；注意 shrine.tscn 建築/手水舍 實際 transform 為 5.0（其 metadata 仍寫 3.2，已過期）
- 耗時：幾何 10.7 s、拍攝 11.9 s、分析 3.1 s

| 區段 | PASS | WARN | FAIL | UNKNOWN | REVIEW |
|---|---:|---:|---:|---:|---:|
| Geometry | 2 | 0 | 0 | 0 | 0 |
| Visual | 19 | 0 | 0 | 0 | 0 |
| Style／Structure | 2 | 0 | 0 | 2 | 0 |
| **合計** | **23** | **0** | **0** | **2** | **0** |

## 最終判定：**UNKNOWN**

| 規則 | 幾何 | 視覺／審查證據 | 最終 |
|---|---|---|---|

## UNKNOWN（2）
- `STYLE:roof_overhang_ratio` [Style／Structure] 物件 []：沒有可辨識的屋頂與柱牆構件（單網格或未分類），無法量出挑　實測 null
- `STRUCT:opaque` [Style／Structure] 物件 ['japanese shrine 3d model', 'stone water basin 3d model']：單一網格（Tripo）：內部構件無法辨識，柱梁屋頂關係無法驗證；不為此重建資產　實測 null

## PASS（23）
`DETACHED`, `SELF_CROSSING:stone water basin 3d model#island0`, `VIS_RELIABLE:front`, `VIS_SCALE:front`, `VIS_RELIABLE:back`, `VIS_SCALE:back`, `VIS_RELIABLE:left`, `VIS_SCALE:left`, `VIS_RELIABLE:right`, `VIS_SCALE:right`, `VIS_RELIABLE:top`, `VIS_SCALE:top`, `VIS_RELIABLE:oblique`, `VIS_RELIABLE:corner0`, `VIS_RELIABLE:corner1`, `VIS_RELIABLE:corner2`, `VIS_RELIABLE:corner3`, `VIS_REPEAT:front`, `VIS_MAPPING`, `VIS_GROUND`, `VIS_SYMMETRY`, `STYLE:height_to_width`, `STYLE:depth_to_width`

## 圖
- D:\神社\shrine\docs\visual_qa\temizuya\capture\views_sheet.jpg
