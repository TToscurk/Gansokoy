# 人間之里：現行生成規格

本文件只保留修改現行人間之里時必須知道的規則。2026-08-10 以前的逐輪實作與
驗證紀錄已封存於 `docs/archive/ningen-no-sato-production-history-2026-08-10.md`；
更早的街區重構日誌在 `docs/archive/ningen-no-sato-redesign.md`。除非決策有爭議，
不要讀取封存文件。

## 現況

| 項目 | 正式來源 |
|---|---|
| 場景 | `godot/maps/village/village.tscn` |
| 生成入口 | `godot/tools/gen_town.gd` |
| 責任模組 | `godot/tools/town/*.gd` |
| 地圖設定 | `godot/data/village.meta.json` |
| 建物尺寸／錨點 | `godot/data/town_modules.json` |
| 固定種子 | `20260806` |

`gen_town.gd` 必須保留。它負責 orchestration、shared state、RNG ownership 與
輸出組裝；地形、路網、街區、建物、地標、市場、密度、河岸、生態、草層、驗證
與輸出等實作位於 `tools/town/`。

舊 `gen_village.gd` 已刪除，不得復活或執行。需要歷史內容時查 Git。

## 命名

- 正式名稱：**鯢吞亭**（繁體）／**鲵吞亭**（簡體）。
- **鵜吞亭**是舊檔歷史誤字，不得搬回程式、場景、資料或文件。

## 不可破壞的生成契約

1. 不改道路中心線、河道、主要地標、portal、保留區、建物數與現有座標。
2. 不改 RNG 呼叫次序。責任模組接受主入口提供的狀態，不自行建立另一套 ownership。
3. 不重寫演算法來配合模組化；搬移函式時保持呼叫順序及參數語意。
4. 建物碰撞與跨水判定使用實測 `gbox`／OBB，不以 `fw/fd` 猜外框。
5. 碰撞 shape 的 `owner` 必須是輸出場景根節點，否則不會存進 `.tscn`。
6. 已有真內容的地標不得再生成 placeholder mesh 或 placeholder collider。
7. 驗證只信成品：`.tscn`、instances JSON、MultiMesh buffer、GLB 頂點及引擎畫面。

## 座標與空間

- 村座標 `-z = 北`，廣場中心 `PLAZA = (0, 30)`。
- glTF 使用 Y-up；Godot 座標映射為 `(bx, bz, -by)`。
- 河道 `RIVER_SPINE` 是結構脊椎，不是裝飾格線。
- 路網是折線：本通、東西大街、橫街、縱街與兩條門引道；不得當成規則格線重建。
- `town_modules.json` 的 `fw/fd/h`、`gbox` 和 facade anchors 由資產工具實測。

## 生成與驗證

新 GLB 必須先完成 Godot import，再生成場景：

```text
godot --headless --path godot --import
godot --headless --path godot --script tools/gen_town.gd
```

最低靜態閘門：

```text
godot --headless --path godot --script tools/check_map.gd
godot --headless --path godot --script tools/walk_test.gd
godot --headless --path godot --script tools/lm_ghost.gd
godot --headless --path godot --script tools/portal_test.gd
godot --headless --path godot --script tools/hieda_boundary_check.gd
```

結構重構還必須比較前後 node count、instance stable hash 與 MultiMesh stable hash。
任一 hash 漂移就停止，不以「只是重構」為理由接受差異。

靜態檢查抓不到材質、比例、視線、浮蓋與美術閱讀問題，因此視覺變更必須另走：

```text
prototype/slice → fixed-camera render → Human Art Review → rollout
```

## 常見復發問題

| 症狀 | 常見原因／處理 |
|---|---|
| 新 MultiMesh 整層消失 | GLB 尚未 import，或錯把整批 MultiMesh 設距離裁切 |
| 檢查全綠但畫面錯 | 靜態檢查不懂構圖；一定要看固定鏡位 render |
| 建物浮空／半埋 | 只取中心地面高度；長 footprint 應量最低地面或正確錨點 |
| 碰撞或保留區錯位 | 未把旋轉／縮放納入世界 OBB/AABB |
| 改一處後全村散佈漂移 | 在循序 RNG stream 中新增、刪除或重排呼叫 |
| GLB 只顯示一個零件 | building asset 違反 single-mesh contract；回 exporter 合併，不在 runtime 偷合併 |
| 面片全黑 | 共面或退化法線；錯開表面或修正面方向 |

## 地標與範圍

六座正式地標為寺子屋、鈴奈庵、鎮守之杜、市場、足洗邸與稗田邸；全部已有真內容。
市場另含龍神像、水井、高札場及攤位。兩座村門為北門與西南門。

稗田邸使用完整版 blockout 與獨立植栽資料，直接位於 village map，並連接
`hieda1f`／`hieda2f`／`hieda3f`。舊村內縮小程序版已刪除，不得重建。

## 已知未結項目

- lighting / cel-shading 尚未完成。
- 稗田邸 blockout 近景材質仍偏平。
- 水面與濕灘寬度、睡蓮幾何仍需獨立決策。
- 鐘塔、火見櫓、近景小物與手工 LOD 仍有品質債。
- 農田、人群／NPC 模擬與祭典幟旗不屬於目前生成器整理範圍。

## 文件邊界

- 當前狀態：`docs/PROJECT_STATE.md`
- 美術方向：`docs/village-art-direction.md`
- 町家資產契約：`docs/machiya-production-kit.md`
- Generator vocabulary／ADR：`docs/domain-model.md`
- 歷史與逐輪證據：`docs/archive/`，只有爭議時才讀
