# 稗田邸：現行規格

本文件只保留修改稗田邸時必須知道的正式狀態與契約。2026-08-11 以前的外觀、
庭園、三層內裝及搬遷逐輪紀錄已封存於
`docs/archive/hieda-estate-features-production-history-2026-08-11.md`。
除非需要追查決策，不要讀封存版本。

## 現行組成

| 內容 | 正式來源 |
|---|---|
| 人間之里內的完整院落 | `godot/assets/models/hieda_blockout.glb` |
| 庭園植栽擺位 | `godot/data/hieda_garden.instances.json` |
| 植栽發射器 | `godot/tools/gen_hieda.gd` |
| 村圖組裝 | `godot/tools/town/town_landmarks.gd` |
| 一樓玄関／客間 | `godot/maps/hieda1f/hieda1f.tscn`、`tools/gen_hieda1f.gd` |
| 二樓阿求書房 | `godot/maps/hieda2f/hieda2f.tscn`、`tools/gen_hieda2f.gd` |
| 三樓大書庫 | `godot/maps/hieda3f/hieda3f.tscn`、`tools/gen_hieda3f.gd` |

稗田邸不是另一套縮小村內版本。使用者已定案：完整院落直接位於人間之里北緣，
舊程序化縮小版不得復活。

## 院落契約

- blockout 靜態幾何約 22,600 面、1 surface／1 draw call。
- 庭園由 10 種模組、136 個實例組成，必須讀取同一份 instances JSON；不得把
  擺位另抄進 `.tscn`。
- 保留區中心約 `(-80.5, -195.8)`，範圍 `97.0 × 118.5 m`。
- blockout 實測跨度約 `96.7 × 117.2 m`，不得超出保留區。
- 外參道接上 `z=-135` 橫街；道路、河道和其他地標不得為它重新改線。
- blockout 使用 `needs_trimesh`，碰撞在執行期建立；`.tscn` 沒有對應 StaticBody
  不代表碰撞遺失。
- blockout 材質需雙面顯示；Blender 中可見不代表 Godot 背面剔除後仍完整。
- 外緣 3～9 m 緩衝環帶使用 46 株疏林，屬於村落與豪邸的視覺過渡。

## 美術方向

稗田邸是「高規、克制、略帶超現實」的豪邸，不是放大的普通町家。

- 主屋：陡峭屋頂、誇張軒反り、腰簷、粗京間木柱與唐破風玄関。
- 前庭：正式切石參道、格子塀、棟門、狛犬、石燈籠及框景巨樹。
- 後院：水池、涸れ滝、枯山水、菜園、飛石、木戶與懸浮裂光景石。
- 庭園需要疏密、框景與迂迴，不做均勻散點或球體樹冠。
- 三樓大書庫是唯一可大量使用「內部比外部大」超現實語彙的室內。

## 內裝方向

- 一樓玄関／客間：對外接待與儀式性；家具低矮、擺設克制，朝向前庭。
- 二樓阿求書房：普通少女的生活尺度，對比千年記錄累積的數量與時間感；不得靠
  身形尺寸異常表現。
- 三樓大書庫：書架向上沒入陰影，空間神聖但仍需維持可走性。
- 三層是獨立場景，不進世界地圖 registry；以 portal 串成
  `village ↔ hieda1f ↔ hieda2f ↔ hieda3f`。
- 窗外使用簡化背板，不能因假窗而製造可穿越出口。

## 生成與驗證

```text
blender -b -P godot/assets/blender/make_hieda.py -- godot/assets/models
godot --headless --path godot --import
godot --headless --path godot --script tools/gen_town.gd
godot --headless --path godot --script tools/gen_hieda1f.gd
godot --headless --path godot --script tools/gen_hieda2f.gd
godot --headless --path godot --script tools/gen_hieda3f.gd
```

最低閘門：

```text
godot --headless --path godot --script tools/check_map.gd
godot --headless --path godot --script tools/walk_test.gd
godot --headless --path godot --script tools/portal_test.gd
godot --headless --path godot --script tools/hieda_boundary_check.gd
```

視覺變更還必須做固定鏡位的門外、參道、玄関近景、後院及鳥瞰 render，再交由
Human Art Review。靜態閘門抓不到平面材質、穿插觀感與構圖問題。

## 不可重開

- 完整版院落直接放在人間之里；不再維護縮小程序版。
- 河道維持原路徑，稗田邸不要求重新規劃街網。
- 三層內裝維持獨立場景及既有 portal 拓撲。
- 植栽擺位以 `hieda_garden.instances.json` 為單一來源。
- 木戶 marker 的 `target: null` 是尚未定案的故事出口，不得擅自連線。

## 已知風險

- `hieda_blockout.glb` 主要靠頂點色，近景牆面與屋瓦比町家平；改善需在 Blender
  拆材質 surface 或建立明確 shader 契約，不在 Godot 隨機覆材質。
- 庭池石組、松樹尺度及部分近景小物仍有品質債。
- 屋頂視差與靠近玩家時的屋頂裁剪仍是儲備方向，尚未成為正式管線。
- 任何重新匯出都要檢查 footprint、trimesh、雙面材質、136 個植栽實例與 portal。
