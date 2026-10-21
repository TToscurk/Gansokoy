# Visual QA：s01_torii_a

- 模式：full　profile：japanese_gate　canon：None
- git c4be7e64（yoriichi-combat-and-village-routing）　2026-10-22 04:21:08
- Godot：4.7.2-stable (official)　renderer：forward_plus　GPU：NVIDIA GeForce GTX 1070
- 縮放：1　來源：GLB 原尺寸
- 耗時：幾何 1.2 s、拍攝 10.3 s、分析 2.9 s

| 區段 | PASS | WARN | FAIL | UNKNOWN | REVIEW |
|---|---:|---:|---:|---:|---:|
| Geometry | 5 | 0 | 0 | 0 | 0 |
| Visual | 19 | 1 | 0 | 0 | 0 |
| Style／Structure | 3 | 0 | 0 | 0 | 0 |
| Visual review | 0 | 0 | 0 | 0 | 1 |
| **合計** | **27** | **1** | **0** | **0** | **1** |

## 最終判定：**REVIEW**

| 規則 | 幾何 | 視覺／審查證據 | 最終 |
|---|---|---|---|
| `torii_on_base` | PASS | REVIEW:0:REVIEW | **REVIEW** |
| `torii_centered_on_base` | PASS | VIS_OFFSET:torii_centered_on_base:PASS, REVIEW:0:REVIEW | **REVIEW** |
| `torii_self_symmetric` | PASS | VIS_SYMMETRY:PASS, REVIEW:0:REVIEW | **REVIEW** |
| `base_self_symmetric` | PASS | VIS_SYMMETRY:PASS | **PASS** |

## REVIEW（1）
- `REVIEW:0` [Visual review] 物件 ['s01_torii_a']：幾何與視覺不一致（透視視角，先用正交視圖確認）；不修改模型，交給人確認　實測 {"image": "corner3.png", "px": [804, 352], "concern": "floating", "observation": "corner3 透視：右側貫的外伸端亮面與暗邊交界很強，乍看像分離的方塊，但看不到背景縫"}　圖：corner3.png

## WARN（1）
- `VIS_GROUND` [Visual] 物件 []：最低點在地面下 0.322 m（埋入）：若是基座設計，在連接表宣告 ground_embed_max；否則檢查原點　實測 {"lowest_y": -0.3223}

## PASS（27）
`torii_on_base`, `torii_centered_on_base`, `torii_self_symmetric`, `base_self_symmetric`, `DETACHED`, `VIS_RELIABLE:front`, `VIS_SCALE:front`, `VIS_RELIABLE:back`, `VIS_SCALE:back`, `VIS_RELIABLE:left`, `VIS_SCALE:left`, `VIS_RELIABLE:right`, `VIS_SCALE:right`, `VIS_RELIABLE:top`, `VIS_SCALE:top`, `VIS_RELIABLE:oblique`, `VIS_RELIABLE:corner0`, `VIS_RELIABLE:corner1`, `VIS_RELIABLE:corner2`, `VIS_RELIABLE:corner3`, `VIS_REPEAT:front`, `VIS_MAPPING`, `VIS_SYMMETRY`, `STYLE:height_to_width`, `STYLE:depth_to_width`, `STRUCT:plinth>torii`, `VIS_OFFSET:torii_centered_on_base`

## 圖
- D:\神社\shrine\docs\visual_qa\s01_torii_a\capture\views_sheet.jpg
