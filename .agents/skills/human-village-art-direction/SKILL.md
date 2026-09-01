---
name: human-village-art-direction
description: Use when designing or reviewing Human Village visuals.
---

# Human Village Art Direction

本 Skill 管理人間之里的格局、環境構圖、建築、地面、植被與視覺驗收。
概念圖是空間權威，不是氣氛參考；使用者只負責視覺裁決，agent 負責把圖像翻譯成候選格局、Godot blockout 與比較證據。

## Authority

依序遵守：

1. 使用者本輪明確裁決。
2. `AGENT_CONSTITUTION.md`。
3. `docs/reference/人間之里概念圖/村落農村概念俯視.png`。
4. `村落農村概念俯視區域分隔.png`。
5. 資料夾內其他現存概念圖。
6. 專案設計文件與既有場景。

硬規則：

- 圖像高於文字轉錄；既有場景不得反過來改寫對圖像的判讀。
- 美術透視圖不是正射地圖，不得把像素位置假裝成精確世界座標。
- 先記錄可見的相鄰、方向、密度、開闊度與視線關係，再估算比例與座標。
- 不確定內容標為 `unknown`，不得自行補成事實。
- 每項判斷標註來源與信心程度：`high`、`medium`、`low`。
- 使用者不必提供技術座標；agent 必須先提出可看的候選方案。

## Mandatory Routing

村莊總平面、道路、河流、水渠、農田、森林輪廓、植被密度、地標、視線、高空構圖或地面分區都必須載入本 Skill。

涉及 Godot 時另外載入：

- `godot-master` 與該次工作的單一對應 reference。
- `level-design`：格局、道路、視線、動線與 blockout。
- `godot-visual-review`：固定機位與視覺驗收。

## Required Pipeline

```text
Concept Audit
→ Layout Contract
→ Pure Blockout
→ Fixed-Camera Comparison
→ Human Layout Review
→ Ground-Level Review
→ Dressing Prototype
→ Human Art Review
→ Rollout
```

前一階段未通過，不得用材質、樹木、燈光或小物掩蓋問題。

## Stage 0 — Verify Evidence

1. 直接查看本輪權威概念圖，不以文字轉錄代替。
2. 用 godot-ai MCP 查 `editor_state`、目前場景、節點與資源實況。
3. 若編輯器有未存變更，先保存並重開場景再操作。
4. 分開記錄圖像證據、使用者裁決、MCP 實況與文件資訊。

完成條件：權威圖、場景實況與證據來源均已列明。

## Stage 1 — Layout Contract

在 `docs/layout/human-village-layout-contract.json` 保存：

- 權威圖與版本。
- 圖像方向、Godot 世界方向與尚未校準的轉換。
- 主錨點：南端大鳥居、主街、北面林丘社寺、東側農田、北／東北主河、穿村細渠、東北河中龍神像。
- 區域：市集、住商混合、住宅、農田、密林、疏林、河岸林帶、水系、開放視野與禁植區。
- 關係：相鄰、包含、連接、視覺終點、密度梯度。
- 每項來源、信心與批准狀態。

座標尚未由圖像與固定鏡頭校準時保持 `null`；禁止製造虛假的精度。

完成條件：主要區域與地標至少具有拓樸關係；狀態只能是 `LAYOUT_PROTOTYPE`。

## Stage 2 — Pure Blockout

只能使用純色平面、簡單方塊、Cyclops primitives、無正式材質的道路／水面，以及代表林冠的大型綠色團塊。

禁止：

- 正式 Meshy 建築與樹木。
- 市集攤位、燈籠與小物。
- 高品質 shader、後期與材質精修。
- 只做漂亮局部而未完成全村骨架。

完成條件：移除材質與光照後，高空仍能辨認主街、林丘、農田、河流、森林與主要地標關係。

## Stage 3 — Fixed-Camera Comparison

輸出同一比例的：

1. 權威概念圖。
2. Godot blockout。
3. 50% 疊圖。
4. 並排圖與差異輔助圖。

必查：主街角度與終點、區域相對位置與面積、森林輪廓、河流拓樸、地標象限、開闊面與密集面。

不得以「之後加材質會更像」「只是原型」「大致有感覺」判定通過。刻意偏離必須附使用者裁決。

完成條件：產出比較證據並進入 `LAYOUT_REVIEW`；只有使用者能給 `LAYOUT_APPROVED`。

## Stage 4 — Ground-Level Review

`LAYOUT_APPROVED` 後依序檢查：

- 50m：村莊輪廓、林丘高程、密度、農田開闊度、水系與地標。
- 20m：街道圍合、街廓節奏、巷道、橋頭、水岸與視線。
- 5m：磨耗、排水、植被邊緣、入口、材質與功能性小物。

不得用 5m 細節掩蓋 50m 或 20m 的失敗。

## Stage 5 — Terrain and Vegetation

只有 `LAYOUT_APPROVED` 後才能進入。

- Terrain3D 或既有地形系統的遮罩必須服從已批准區域。
- 森林地面至少區分腐植／落葉、裸土、草苔、岩石、灌木與明暗層。
- ProtonScatter、Terrain3D foliage 或生成器只能在批准的植被區域內工作。
- 密林、疏林、林緣、河岸林帶、庭院樹、禁植區與視線保護區分開製作。
- 禁止用一個全村矩形隨機撒樹，或以株數代替林冠輪廓。

## Tool Roles

- Concept comparison script：圖像尺寸、並排、疊圖與差異輔助。
- Cyclops：全村 blockout。
- Terrain3D：地形雕刻與地表分區。
- ProtonScatter：只在批准區域內散布植被。
- AssetPlacer：手動放置地標與構圖關鍵物件。
- Godot AI MCP：實況查詢、場景操作與結構驗證。

外掛不能自行決定格局；所有工具服從 Layout Contract。

## Stop Conditions

以下任一成立即停止 dressing：

- 高空輪廓與概念圖大相逕庭。
- 主地標位於錯誤象限。
- 主街入口、方向或視覺終點不成立。
- 森林侵入農田或主要開放面。
- 河流拓樸不同且沒有使用者裁決。
- 只能靠材質或光照讓畫面感覺比較像。
- 需要移動主要地標或改變村莊結構。

保留可重用資產，把錯誤格局標為 `LAYOUT_REJECTED`；不得繼續提高錯誤骨架的完成度。

## Review States

合法狀態：

- `LAYOUT_PROTOTYPE`
- `LAYOUT_REVIEW`
- `LAYOUT_APPROVED`
- `LAYOUT_REJECTED`
- `ART_PROTOTYPE`
- `ART_REVIEW`
- `ART_APPROVED`
- `ART_REJECTED`

只有使用者能給 `LAYOUT_APPROVED` 與 `ART_APPROVED`；沉默不等於批准。

## Verification

聲稱格局完成前必須提供：

- 權威概念圖名稱。
- Layout Contract 版本與狀態。
- Godot 場景路徑與固定機位。
- 概念圖／blockout 比較圖。
- 區域差異與刻意偏離清單。
- MCP 結構查詢。
- 50m、20m、5m 截圖。
- 尚未解決項目與使用者批准狀態。

缺少任何一項，不得聲稱格局符合概念圖。
