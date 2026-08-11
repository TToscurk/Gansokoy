# 町家 Production Kit：現行規格

本文件是町家資產與 Blender → GLB → Godot 管線的正式契約。Phase 1～2.6b 的
逐輪製作、審圖與除錯紀錄已封存於
`docs/archive/machiya-production-kit-production-history-2026-08-11.md`。
除非需要追查決策，不要讀封存版本。

## 正式管線

```text
make_machiya.py / make_town.py
  → assets/models/machiya_*.glb
  → data/town_modules.json
  → gen_lib.semantic_mesh()
  → tools/town/*
  → MultiMesh / village.tscn
```

- `make_town.py` 是 `town_modules.json` 的唯一 writer。
- 尺寸、`gbox` 與 facade anchors 必須從匯出幾何實測，不得手抄猜值。
- `gen_town.gd` 持有生成順序與 RNG；町家模組只消費輸入狀態。
- 建物 GLB 必須符合 single-mesh contract。多個 MeshInstance 需在 exporter 合併，
  不得在 runtime 偷合併。

## Production Modules

以下尺寸為目前 `town_modules.json` 的 `fw × fd × h`：

| 模組 | 尺寸 m | 角色 |
|---|---:|---|
| `machiya_f_a` | 9.56 × 9.53 × 5.42 | 標準平入町家；結構基線 |
| `machiya_f_s` | 7.16 × 8.50 × 4.87 | 低矮仕舞屋 |
| `machiya_f_o` | 11.76 × 10.47 × 6.17 | 大店、五開間、卯建 |
| `machiya_t_a` | 7.96 × 10.66 × 5.72 | 妻入町家 |
| `machiya_w_a` | 9.16 × 9.31 × 5.75 | 工房、大戶口、煙出し |
| `machiya_f_n` | 9.96 × 9.90 × 6.42 | 真二階町家 |
| `machiya_e_p` | 7.94 × 7.88 × 4.17 | 村緣平屋 |
| `machiya_f_m` | 10.74 × 9.29 × 4.62 | 低層寬間口商家 |
| `machiya_n_a` | 11.14 × 9.29 × 7.67 | 總二階 |
| `machiya_n_o` | 12.34 × 9.69 × 8.55 | 總二階大店 |

`machiya_f_b`、`machiya_b_a`、`machiya_b_b`、`machiya_e_a` 是 layout vocabulary
中的 legacy source kinds；`town_config.gd` 會將它們替換成 production 模組。
它們仍被 layout、manifest 與資產檢查引用，不能只因村圖實例數為 0 就刪除。

## 建築語言

- 真壁造：柱樑先成立，漆喰逐格內縮；陰影線由幾何形成，不靠畫線貼圖。
- 共通文化由內法線、軒高帶、材質族與瓦語彙維持；variation 來自間口、開間、
  屋頂方向、樓層、庇、腰板與職業構成。
- 妻入不是把平入 mesh 旋轉 90°；屋頂跨度、軸組與立面必須重新生成。
- 普通住宅不得靠任意 scale／rotation 假裝另一種家族。
- 主街與市場可使用較強的商業／上層剪影；村緣保持低矮、樸素。

## 語意材質契約

標準材質族：

```text
WOOD / WOOD_LT / PLASTER / STONE / KAWARA / SHOJI
```

- Blender 材質名沿 GLB primitive 進入 Godot，`semantic_mesh()` 按名稱前綴換成
  專案 PBR 材質。
- 比對必須長名前置，避免 `WOOD` 吃掉 `WOOD_LT`。
- 對不上的名稱保留 GLB 原材質並報錯／警告，不得猜測成任意材質。
- 工房等建築可以沒有 SHOJI，但 production building 不得退化成單一 surface。
- 材質結構改變後必須重新 Godot import；只重跑 Blender 不足以刷新舊匯入結果。

## Facade 與布料契約

- 店面身分用構圖表達：暖簾、招牌、貨架、工作區與貨物形成職業語彙，不做均勻
  隨機撒物。
- 吊掛高度必須從 manifest 的 `facade.hisashi`／`facade.eave` 平面計算；不得再寫
  絕對高度。
- 布料先解決擺位與屋簷淨空，再使用形變 guard rail；自動縮形不能掩蓋錯誤配置。
- 妻入屋頂的軸向不同；沒有經過軸交換驗證前，不得把平入 soffit 公式套上去。
- 暖簾分片需有可讀縫隙、輕微深度差和克制的靜態形變，不能看成一整塊硬板。

## 生成

```text
# Prototype 與中性光審圖
blender -b -P godot/assets/blender/make_machiya.py -- \
  godot/assets/models --render godot/art_review/phase1_machiya_f_a

# 全模組庫與 manifest
blender -b -P godot/assets/blender/make_town.py -- godot/assets/models

godot --headless --path godot --import
godot --headless --path godot --script tools/asset_dims_check.gd
godot --headless --path godot --script tools/gen_town.gd
```

## 驗證

- Blender：退化面 0、鬆散頂點 0、bbox／gbox 實測、材質族存在。
- GLB：單一 mesh、production building 多 surface、material names 正確。
- `asset_dims_check.gd`：實測尺寸與 manifest 差異不得超過 0.05 m。
- Village：建物 OBB 0 重疊、道路／河道／地標／portal 不漂移。
- 結構重構：node count、instance stable hash、MultiMesh stable hash 必須一致。
- 視覺：中性光 lineup 同時確認「同一文化」與「不是同一棟房」；再以固定鏡位
  slice／村圖檢查眼高、轉角、屋簷、店面和背光。

最低靜態閘門：

```text
godot --headless --path godot --script tools/check_map.gd
godot --headless --path godot --script tools/walk_test.gd
godot --headless --path godot --script tools/lm_ghost.gd
godot --headless --path godot --script tools/portal_test.gd
```

## 不可重開

- `machiya_f_a` 是 production 結構基線，不因偏好重新改比例。
- `town_modules.json` 維持單一 writer。
- frontage／parcel／OBB 與道路結構不因換資產而改寫。
- 建物材質走 semantic surface，不退回 `prop_mesh()` 的整棟單材質路徑。
- 視覺 rollout 必須先通過 prototype/slice 與 Human Art Review。

## 已知風險

- 卯建仍偏貼牆板，不像連續防火妻壁。
- 屋頂家族仍以切妻為主，入母屋、落棟與下屋變化不足。
- 背光漆喰偏冷灰，屬於 lighting／cel-shading 階段。
- 手工 LOD 尚未完成，production geometry 成本高於 legacy blockout。
- 近景小物、空白招牌與部分布料風向仍有品質債。
