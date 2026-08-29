# 幻想鄉緣一計畫：Production Constitution

> 2026-08-29 使用者審定精簡版。原版為一個月開發中 AI 累積寫成；本版由使用者裁決：
> 保留技術事實與使用者核准的門檻，砍除 AI 自建的流程官僚（模式宣告、KPI 報表、時間盒、啟動清單）。

## 1. 目標

以最短時間做出玩家**看得見、走得到、可展示**的品質提升。
基線：現行 `village.tscn` 地標區。預設 20% 修舊 / 80% 新美術。
不要用內部整潔、架構優雅或測試數量冒充玩家可見進度。

## 2. 紅線

1. 先重用，後新增；不建平行 pipeline、驗證器或第二套資料來源。
2. 沒有阻塞就不重構核心（generator、RNG、道路、Portal、世界生成）。
3. 不順手擴張範圍，不過度工程。
4. 只有使用者能批准視覺工作（`ART_APPROVED`）；agent 至多到 `ART_REVIEW`。
5. 替換或移除比修補快就替換；不無限打磨低價值資產。
6. `godot/assets/blender/sources/` 唯讀，不得編輯、改名、移動或刪除。

## 3. 證據優先（MCP 政策）

1. 涉及場景／節點／資源狀態：**先用 godot-ai MCP 查實際狀態**（editor_state／scene／node 等），
   不讀文件推測、不依檔名或記憶猜。
2. 結構驗證用 MCP 查詢；**視覺驗收才截圖**，截圖一律用 shotlist 固定機位
   （`godot/tools/shots/*.json` + `tools/capture-godot.cmd`）。
   渲染類問題（剔除、繞線、shader、摩爾紋、光照）只有截圖能抓——資料層查不到，
   本專案歷史上所有「看起來不對」的缺陷全是截圖抓到的。
3. Skill 按需載入，不是開工儀式：`godot-master` 只在查證 Godot 技術問題時載入，
   一次一個 reference。場景／關卡 → `level-design`；視覺審查 → `godot-visual-review`；
   Blender 資產 → `blender-asset-production`；美術判斷 → `gensokyo-3d-art-director`／
   `human-village-art-direction`；提交 → `safe-production-commit`。
4. MCP 呼叫逾時不等於失敗：長操作（force_reload、re-import）先用 `editor_state`
   確認再重試；同一時間只允許一個 AI 對編輯器發指令。

## 4. 驗證分級

- **Fast**（日常資產工作）：語法／載入、GLB、尺寸、材質遺失、showcase render。
  呼叫既有檢查，不重寫檢查邏輯。
- **Full**（整合、release、placement／world-generation 變更）：整村生成、overlap、
  map/walk/landmark/Portal、runtime smoke 等完整 regression。
- Fast 失敗先局部修；問題跨越資產邊界或實際進入整合才升級 Full。
  不得因「比較安心」每件資產都跑 Full。

## 5. 美術生產

- 開工前寫短 Art Card：用途、第一眼 silhouette、第二眼細節、色彩材質、明確禁止項。
- 統一 showcase：Front、45°、Side、Rear、Silhouette 五視角；不為拍 proof 新增永久 scene。
- 三距離 Review：50m 量體／skyline → 20m 街道節奏／色塊 → 5m 材質細節。
  不得用 5m 細節掩蓋 50m/20m 的失敗；交付圖標示評估距離。
- 流程：prototype → render → **Human Art Review** → rollout，不可跳步。
  未批准資產不得大量灌入村莊；prototype 的批准不等於全村 rollout 的批准。
- 美術方向是**可遊玩的幻想鄉**，不是歷史日本博物館。

## 6. 行為

- 先交付結論與可見證據，再說內部工作。
- 已批准方向就自主執行到底，不要微批准。只在這些情況前停下來問：
  移動主要地標、改村莊結構、改已核准美術方向、改玩法／世界觀、
  無安全回滾的破壞性操作。
- 不盲從要求；方向違反本文件或成本效益差時，以證據提出更小、更正確的替代方案。
- 詳細 lore、Art Bible、資產規格、命令與測試清單以各自權威文件為準；本文件不複製它們。
