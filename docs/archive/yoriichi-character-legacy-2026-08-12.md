# 緣一角色製作規格

## 目前狀態

`YORIICHI_Y02_REBUILD — BODY_PROPORTION_GATE + IDENTITY_SILHOUETTE_GATE`

技術狀態：`TECH_PASS`。美術狀態：`ART_REVIEW`。只有使用者可以標記
`ART_APPROVED`。

本輪是獨立 `ART_FAST` 人物線；不得修改人間之里 generator、道路、配置、Portal、
環境美術、玩家移動或碰撞。兩道 Gate 核准以前，不開始細節、Rig、動畫或正式
Player 整合。

## Art Card

- 感覺：安靜、克制、優雅、壓倒性可靠，不做誇張戰鬥姿勢。
- 第一眼：長紅黑髮、深紅羽織、高瘦比例、左腰刀鞘斜線。
- 第二眼：火焰狀斑紋、花札耳飾、深色隊服、日輪刀金屬件。
- 材質：動畫式清楚分區、低反光、可供日後賽璐璐化；不建全域 shader。
- 禁止：寫實皮膚、Q 版、肌肉狂戰士、重甲、飾品堆疊、布料模擬與塑膠玩具感。

## Y01 視覺目標

`shots2/yoriichi_character_track_01/y01_visual_target.png` 是正式拓樸與造型下一輪的
視覺目標，不是 3D 完成證據。應優先追上：

1. 約七點五至八頭身的高瘦成人比例。
2. 後綁、分層的大髮束輪廓，而不是細碎髮絲。
3. 深沉酒紅羽織、自然下垂袖形與膝上長度。
4. 寬鬆下裝、腳踝綁帶與較輕的鞋腳量體。
5. 安靜中性的臉，不靠表情演出辨識度。

## 舊 Y02：TECH_DUMMY / ART_REJECTED

- 生成入口：`godot/assets/blender/make_yoriichi_prototype.py`
- Blender source：`godot/assets/blender/sources/yoriichi_base_prototype.blend`
- GLB：`godot/assets/models/yoriichi_base_prototype.glb`
- 審視圖與量測：`shots2/yoriichi_character_track_01/`

舊 Y02 只保留作尺度、匯出與失敗比較，不得修漂亮、上骨架、製作動畫或成為正式
角色基底。其方形頭身、硬板羽織、短厚比例與玩具感已構成結構性否決。

## Production Base Candidate

- 生成入口：`godot/assets/blender/make_yoriichi_production_base.py`
- Blender source：`godot/assets/blender/sources/yoriichi_production_base.blend`
- GLB：`godot/assets/models/yoriichi_production_base.glb`
- Gate 圖與量測：`shots2/yoriichi_character_rebuild/`

新基底從零建立，不匯入或修改舊 Y02。BODY Gate 使用獨立人體、成人頭部基形與
landmark 線；Identity Gate 只增加曲線髮量、羽織大形、袴、綁腿與刀鞘。最終臉、
斑紋、耳飾、鈕扣、UV、材質精修、Rig、動畫及 Player 整合維持鎖定。

## 穩定尺度契約

| 項目 | 契約 |
|---|---|
| 視覺目標身高 | 1.78 m（Production Base 包圍盒約 1.775 m） |
| 頭身 | 7.61 |
| 肩寬 | 0.42 m；身高比 0.236 |
| 胯高 | 0.93 m；身高比 0.522 |
| 膝高 | 0.50 m；身高比 0.281 |
| 現有 Player capsule | 1.70 m 高、0.45 m 半徑；本輪只參照，不修改 |
| Blender 單位 | 1 unit = 1 m |
| Blender 軸向 | +Z up、-Y forward |
| Godot 軸向 | +Y up、-Z forward |
| Origin | 兩腳底之間、地面高度 0 |
| 匯出縮放 | GLB 1.0，不在後續階段靜默改縮放 |

## Gate 狀態

- `BODY_PROPORTION_GATE`：`ART_REVIEW`。數值契約已達成，視覺判斷由使用者決定。
- `IDENTITY_SILHOUETTE_GATE`：`ART_REVIEW`。已具長髮、羽織、寬下裝與左側刀鞘，
  但髮束層次、羽織側面垂墜和袴接腿仍是明確大形風險。

若任一 Gate 被否決，繼續改大形；只有兩道 Gate 都由使用者核准後，才進 Y03
Production Modeling／Face／Clothing Refinement。Rig 仍屬更後階段。
