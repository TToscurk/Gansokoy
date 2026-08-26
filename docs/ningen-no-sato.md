# 人間之里：現行規格（新基線 2026-08-26）

> 使用者裁定：**現行 `godot/maps/village/village.tscn` 就是新基線**。
> 170 戶時代（程序生成管線、町屋資產、市場、村門、portal）已於 2026-08-25
> 全數刪除，屬舊方案，不得尋找、還原或重建。歷史紀錄見 `docs/archive/`。

本文件只保留修改現行人間之里時必須知道的規則。2026-08-10 以前的逐輪實作與
驗證紀錄已封存於 `docs/archive/ningen-no-sato-production-history-2026-08-10.md`；
更早的街區重構日誌在 `docs/archive/ningen-no-sato-redesign.md`。除非決策有爭議，
不要讀取封存文件。

## 現況

| 項目 | 正式來源 |
|---|---|
| 場景（凍結，直接編輯） | `godot/maps/village/village.tscn` |
| 烘焙資產 | `godot/maps/village/gen/`（GLB／`.res`，已提交） |
| 地圖設定 | `godot/data/village.meta.json` |

場景內容（新基線）：地標 鎮守之杜、稗田邸（＋後院）、鈴奈庵、寺子屋、霧雨店、
鯢吞亭、龍神像；14 盞路燈；植被層（Shrubs／Ferns／GrassTall／GrassFlower／
Reeds）；Vista 遠景；Terrain；Boundary；WorldEnvironment。未來的村莊內容在此
基線上疊加，經 Human Art Review 批准後放入。

## 命名

- 正式名稱：**鯢吞亭**（繁體）／**鲵吞亭**（簡體）。**鵜吞亭**是舊檔歷史誤字，
  不得搬回程式、場景、資料或文件。
- 已知未修錯字：場景節點與 `gen/` 資料夾把「稗田邸」寫成「**裨**田邸」。
  改名會牽動場景引用，未經任務明確指定不要動。

## 修改規則

1. 不移動現有地標、不改 Terrain／Boundary 結構，除非任務明確要求。
2. 已有真內容的地標不得放 placeholder mesh 或 placeholder collider。
3. 建物碰撞與空間判定使用實測 `gbox`／OBB，不以名目尺寸猜外框。
4. 碰撞 shape 的 `owner` 必須是場景根節點，否則不會存進 `.tscn`。
5. 驗證只信成品：`.tscn`、MultiMesh buffer、GLB 頂點及引擎畫面。

## 座標與空間

- 村座標 `-z = 北`。glTF 使用 Y-up；Godot 座標映射為 `(bx, bz, -by)`。

## 驗證

新 GLB 必須先完成 Godot import：

```text
godot --headless --path godot --import
```

靜態閘門（工具都在 `godot/tools/`）：

```text
godot --headless --path godot --script tools/check_map.gd
godot --headless --path godot --script tools/walk_test.gd
godot --headless --path godot --script tools/lm_ghost.gd
godot --headless --path godot --script tools/hieda_boundary_check.gd
```

（`portal_test.gd` 仍存在，但新基線場景沒有 portal；有 portal 的地圖才跑。）

靜態檢查抓不到材質、比例、視線、浮蓋與美術閱讀問題，視覺變更必須另走：

```text
prototype → fixed-camera render → Human Art Review → rollout
```

## 常見復發問題（凍結場景仍適用）

| 症狀 | 常見原因／處理 |
|---|---|
| 新 MultiMesh 整層消失 | GLB 尚未 import，或錯把整批 MultiMesh 設距離裁切 |
| 檢查全綠但畫面錯 | 靜態檢查不懂構圖；一定要看固定鏡位 render |
| 建物浮空／半埋 | 只取中心地面高度；長 footprint 應量最低地面或正確錨點 |
| 碰撞或保留區錯位 | 未把旋轉／縮放納入世界 OBB/AABB |
| GLB 只顯示一個零件 | 資產違反 single-mesh contract；回 exporter 合併，不在 runtime 偷合併 |
| 面片全黑 | 共面或退化法線；錯開表面或修正面方向 |
| Blender 看正常、引擎看不見 | 面片繞向錯誤（見 `.claude/rules/godot.md`） |

## 稗田邸

稗田邸直接位於 village map（烘焙 GLB），連接 `hieda1f`／`hieda2f`／`hieda3f`。
邸內樓層仍有活生成器 `gen_hieda*.gd`。細節見 `docs/hieda-estate-features.md`。

## 已知未結項目

- lighting / cel-shading 尚未完成。
- 村莊主體（街道、住宅、市場等）待以新方式重建，方案尚未定案。
- 近景小物與手工 LOD 仍有品質債。

## 文件邊界

- 當前狀態：`docs/PROJECT_STATE.md`
- 美術方向：`docs/village-art-direction.md`
- 歷史與逐輪證據：`docs/archive/`，只有爭議時才讀
