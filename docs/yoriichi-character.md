# 緣一角色製作規格

## 目前狀態

`CHARACTER TRACK 01 — Y01 Visual Target + Y02 Base Prototype`

狀態：`ART_REVIEW`。只有使用者可以標記 `ART_APPROVED`。

本輪是獨立 `ART_FAST` 人物線；不得修改人間之里 generator、道路、配置、Portal、
環境美術、玩家移動或碰撞。Y01/Y02 核准以前，不開始 Rig、動畫或正式 Player 整合。

## Art Card

- 感覺：安靜、克制、優雅、壓倒性可靠，不做誇張戰鬥姿勢。
- 第一眼：長紅黑髮、深紅羽織、高瘦比例、左腰刀鞘斜線。
- 第二眼：火焰狀斑紋、花札耳飾、深色隊服、日輪刀金屬件。
- 材質：動畫式清楚分區、低反光、可供日後賽璐璐化；不建全域 shader。
- 禁止：寫實皮膚、Q 版、肌肉狂戰士、重甲、飾品堆疊、布料模擬與塑膠玩具感。

## Y01 視覺目標

`shots2/yoriichi_character_track_01/y01_visual_target.png` 是正式拓樸與造型下一輪的
視覺目標，不是 3D 完成證據。應優先追上：

1. 約七至七點五頭身的高瘦比例。
2. 後綁、分層的大髮束輪廓，而不是細碎髮絲。
3. 深沉酒紅羽織、自然下垂袖形與膝上長度。
4. 寬鬆下裝、腳踝綁帶與較輕的鞋腳量體。
5. 安靜中性的臉，不靠表情演出辨識度。

## Y02 基礎模型

- 生成入口：`godot/assets/blender/make_yoriichi_prototype.py`
- Blender source：`godot/assets/blender/sources/yoriichi_base_prototype.blend`
- GLB：`godot/assets/models/yoriichi_base_prototype.glb`
- 審視圖與量測：`shots2/yoriichi_character_track_01/`

Y02 是可重生、可匯出、可用於決定大形的非骨架原型。它已拆出頭、身體、四肢、
手足、隊服、腰帶、羽織、主要髮束、斑紋、花札耳飾、刀與鞘；目前不宣稱正式拓樸、
UV、最終材質、Rig 或動畫完成。

## 穩定尺度契約

| 項目 | 契約 |
|---|---|
| 視覺目標身高 | 1.78 m（生成後包圍盒含頭髮約 1.793 m） |
| 現有 Player capsule | 1.70 m 高、0.45 m 半徑；本輪只參照，不修改 |
| Blender 單位 | 1 unit = 1 m |
| Blender 軸向 | +Z up、-Y forward |
| Godot 軸向 | +Y up、-Z forward |
| Origin | 兩腳底之間、地面高度 0 |
| 匯出縮放 | GLB 1.0，不在後續階段靜默改縮放 |

## 下一個 Gate

使用者核准或否決 Y01 比例、臉、頭髮、羽織與整體方向。若否決，先改 Y01/Y02；
若核准，下一輪才做 game-ready cleanup + conventional humanoid Rig。
