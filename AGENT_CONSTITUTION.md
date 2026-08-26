# 幻想鄉緣一計畫：Production Constitution

> Claude Code、Codex 與其他實作 Agent 每次開工前必讀。除非使用者明確覆寫，本文件是本專案的強制生產原則。

## 1. 唯一目標

以最短時間做出玩家**看得見、走得到、可展示**的幻想鄉品質提升。

**基線（2026-08-26 裁定）**：現行 `village.tscn` 就是新基線——地標區（鎮守之杜、稗田邸、鈴奈庵、寺子屋、霧雨店、鯢吞亭、龍神像）＋路燈＋植被＋遠景。舊 170 戶町屋、市場、村門均已隨舊方案刪除，**不存在也不需尋找或還原**。近期 showable slice 為：

**現有地標區的可走可看範圍**（使用者指定新路線前，以此為準）

預設資源配置：**20% 修舊、80% 製作新美術與可見成果**。不要用內部整潔、架構優雅或測試數量冒充玩家可見進度。

## 2. 硬性紅線

1. **禁止平行框架。** 新工具必須取代或薄包裝既有步驟，不得在旁邊建立第二套 pipeline、驗證器、showcase、資料來源或隱藏狀態。
2. **先重用，後新增。** 優先組合既有 Blender、Godot、generator、測試與 capture 工具；不得複製其核心邏輯。
3. **沒有阻塞就不重構核心。** 不得主動重構 generator、RNG、道路、Portal、lot placement 或世界生成核心。只有它們直接阻止 showable slice，且有可重現證據時才可提出最小修改。
4. **禁止順手擴張範圍。** 不因「既然來了」而改架構、格式、命名或無關資產。
5. **禁止過度工程。** 不為目前沒有的規模建立 scheduler、database、task server、通用插件系統或大型抽象層。
6. **TECH PASS 不等於 ART PASS。** Agent 不得宣稱視覺完成或自行標記 `ART_APPROVED`；只有使用者可以批准。
7. **不永遠打磨低價值壞資產。** 若替換或移除比修補更快、更能改善畫面，就替換或移除；保留相容性所需的最小處理即可。
8. `godot/assets/blender/sources/` 是唯讀參考，不得編輯、改名、移動或刪除；本地鏡像可能不完整，不得捏造缺失資料。

## 3. 每項工作只選一種模式

| 模式 | 適用範圍 | 必須做 | 不得做 |
|---|---|---|---|
| `ART_FAST` | 單件或批次資產、材質、輪廓 prototype | Art Card、統一 showcase、Fast Validation、50m/20m/5m 圖 | 整村重生、Portal/full regression、placement 重構 |
| `INTEGRATION` | 將一批已審視資產放入遊戲 | placement、碰撞、整村生成、Full Validation、路線截圖 | 重新設計資產、無關核心重構 |
| `BUG_SWEEP` | 玩家在展示路線上看得到的硬傷 | 重現、最小修正、針對性驗證、前後對照 | 重構、擴建系統、順便美化無關區域 |

若工作同時混合多種模式，先拆開；不可用最重的流程處理所有小改動。

## 4. 驗證分級

### Fast Validation

用於 `ART_FAST`，目標是幾分鐘內回饋，只驗與該資產直接相關的項目：語法/載入、GLB、尺寸、材質遺失、明顯壞 mesh、showcase render。Fast 必須呼叫既有檢查，不重寫檢查邏輯。

### Full Validation

只用於 `INTEGRATION`、release、placement/world-generation 變更，依既有專案能力執行整村生成、尺寸/overlap、map/walk/landmark/Portal、runtime smoke、instances/meta hash 等完整 regression。

**升級規則：** Fast 失敗先局部修；只有問題跨越資產邊界，或實際進入整合，才升級到 Full。不得因「比較安心」每件資產都跑 Full。

## 5. 美術生產規格

### Art Card：開工前一張短卡

每件或同系列資產只定義：

- 感覺與用途
- 第一眼辨識點與 silhouette
- 第二眼細節
- 色彩、材質與幻想程度
- 明確禁止項
- 少量 reference（連結既有 Art Bible／設計文件，不複製長文）

美術方向是**可遊玩的幻想鄉**，不是歷史日本博物館。優先考慮路線構圖、辨識度、溫度、生活感與世界特色；細節服務於玩家距離，不服務於模型炫技。

### 統一 Showcase

全案只保留一套正式 showcase，可替換 building／prop／tree，固定輸出 Front、45°、Side、Rear、Silhouette。新資產不應為了拍 proof 而新增永久 scene 或專用框架。

### 三距離 Review

- **50m：** skyline、量體、地標、路線導引；讀不出來就先改大形。
- **20m：** 店型、色塊、招牌、屋簷、街道節奏；先解決重複與雜訊。
- **5m：** 材質、道具、接縫、穿模；只投入玩家確實會靠近的細節。

不得用 5m 細節掩蓋 50m/20m 的失敗。交付圖必須標示評估距離。

## 6. Batch 工作流

1. 選擇展示路線上最有可見價值的一批資產（通常 5–20 件，同族群、可共同審視）。
2. 寫短 Art Cards，確認共同語言與禁止項。
3. 在 `ART_FAST` 中製作，使用統一 showcase 與 Fast Validation。
4. 回報每件狀態：`TECH_FAIL`、`TECH_PASS / ART_REVIEW`、`ART_APPROVED`（僅沿用使用者決定）。
5. 只有使用者批准的資產才進正式批次替換；未批准資產不得大量灌入村莊。
6. 進入 `INTEGRATION`，一次 placement、一次 Full Validation、一次展示路線前後對照。
7. 記錄結果與下一個可見批次；不要建立永久追蹤服務。

批次失敗必須能指出單一資產或步驟，讓其單獨重跑，不得讓整批無差別重做。

## 7. 決策與時間盒

遇到選擇時依序判斷：

1. 玩家在現行展示路線（見第 1 節基線）看得到嗎？看不到則降級或不做。
2. 是新增可見價值，還是修舊？若本輪修舊已接近 20%，優先新製作。
3. 能否重用既有工具或刪掉一個步驟？能則不得新增平行工具。
4. 目前是 50m、20m 還是 5m 問題？只解決最高影響距離。
5. 修復與替換何者更快達到 ART REVIEW？預設選替換低價值壞資產。
6. 是否真的被核心阻塞？沒有證據就不碰 generator/RNG/roads/Portal。

時間盒：

- **15 分鐘仍無法選模式或定位工具：** 讀本文件與既有入口文件，縮小任務；不要全面探索 repo。
- **30 分鐘沒有可視 proof：** 先產出灰盒、showcase 或最小前後對照，校正方向。
- **60 分鐘卡在單一低價值資產：** 停止深磨，提出替換、移除或降級方案。
- **長任務每 2 小時至少產出一次批次級可見改善**（多件資產或一段完整街景），並附證據；若做不到，立即重切批次或報告真實阻塞。

時間盒不是降低品質，而是阻止無止境研究與局部拋光。不得為趕時間跳過與風險相稱的驗證。

## 8. KPI：用成果而非忙碌衡量

每輪至少回報：

- 展示路線上新增／替換／移除的可見資產數
- 通過 `TECH_PASS` 與等待 `ART_REVIEW` 的數量；`ART_APPROVED` 僅引用使用者決定
- 50m／20m／5m 前後對照與改善層級
- Fast 與 Full 各自耗時、失敗資產是否可單獨定位
- 本輪修舊／新製作比例（目標約 20／80）
- 新增永久工具數、淘汰舊步驟數（理想：新增 0；若新增，必須移除或取代既有負擔）

「讀了很多檔、跑了很多測試、重構很漂亮」不是 KPI。

## 9. Agent 行為

- 先交付結論與可見證據，再說內部工作。
- 不盲從要求；若方向違反本憲法或成本效益差，應以證據提出更小、更正確的替代方案。
- 小範圍、可逆修改優先；尊重既有使用者變更，不清理無關檔案。
- 不自行宣布美術成功，不用 TECH 指標代替人的視覺判斷。
- 長任務要持續產出可審視成果；不得長時間只做基礎設施。
- 詳細 lore、Art Bible、資產規格、命令與測試清單以各自既有權威文件為準；本文件只定義決策與生產規則，不複製它們。

### Godot 與 MCP 操作規則

- 本專案是 Godot 專案，正式遊戲位於 `godot/`。需要讀取或修改場景、腳本、資源、節點樹，或執行遊戲與除錯時，**必須優先使用 godot-ai MCP 工具**（editor_state／scene／node／material／screenshot 等）取得實際證據；不得只依檔名、舊文件、記憶或推測判定專案狀態。MCP 呼叫逾時不等於失敗——長操作（force_reload、re-import）常超過 5 秒等待，先用 `editor_state` 確認再重試；同一時間只允許一個 AI 對編輯器發指令。
- 任何修改前，必須先確認目標專案、實際相關檔案，以及目前 Git 分支與工作樹狀態，再依檢查結果採取最小修改。若目標目錄沒有 Git metadata、分支無法確認，或所需 MCP／Godot 工具不可用，必須明確回報該限制，不得捏造分支、工具結果或執行中狀態。

### Godot Skill 路由規則

- **按需載入（使用者 2026-08-26 修訂，原「每次強制」因 token 成本過高撤回）**：`godot-master` 是**知識查詢庫，不是開工儀式**。只有在遇到真正需要查證的 Godot 技術問題時才載入——例如不確定 API 用法、效能／物理／shader 行為、匯入或算繪疑難。載入時只讀其決策矩陣指向的**單一 reference**，不得載入整個 SKILL.md 參考庫。
- **不需要載入的情況**（多數任務屬此類）：場景節點增刪改、材質指派、資產擺位、跑既有生成器與 capture、文件更新、憲法既已規定的流程。這些照專案 rules 與既有入口做即可。
- **必要時按需載入其他專案 Skill 執行**：場景設計／道路規劃／3D 佈局／視線／關卡流線 → `level-design`；視覺前後對照與審查 → `godot-visual-review`；Blender→GLB 資產機制 → `blender-asset-production`；美術判斷 → `gensokyo-3d-art-director`／`human-village-art-direction`；提交 → `safe-production-commit`。不再安裝功能重疊的外部 Skill。
- Skill 是專業知識與工作路由，不是第二套 pipeline。使用者當前指示、本文、實際 Godot 版本、專案權威文件與既有 build／capture／validation 入口均優先於通用 Skill；不得用 Skill 規避 Human Art Review、擴張範圍或建立平行工具。
- **禁用 `godot-master` 的平行 QA／建置工作流**：其 Workflow 11–14（Builder 程式化建場景、Agent Vision 截圖評分、Analyst 架構評分、Auditor never-list 掃描）及 `scripts/` 內的對應腳本一律不得使用——它們正是紅線 1 禁止的平行框架。視覺驗證只走本專案 capture 管線與 Human Art Review；架構與程式審查走專案既有 rules 與 skill。`godot-master` 只作為 Godot API／效能／物理等**知識查詢**，且只按需載入單一 reference。其中大量 genre／mobile／multiplayer／2D 內容與本專案無關，不得作為路由依據。

## 10. Agent Startup Checklist

- [ ] 讀完本文件；確認使用者本輪明確要求。
- [ ] 涉及 Godot：確認 godot-ai MCP 連線（`editor_state`）。遇到需查證的技術問題時才載入 `godot-master` 的單一 reference。
- [ ] 宣告唯一模式：`ART_FAST`／`INTEGRATION`／`BUG_SWEEP`。
- [ ] 確認工作直接改善現行展示路線（第 1 節基線），或說明必要阻塞。
- [ ] 設定本輪 20／80 預算、距離層級與可見交付物。
- [ ] 找到並重用既有 build、showcase、validation 入口。
- [ ] 設定 30／60／120 分鐘檢查點。
- [ ] 若是美術，先有短 Art Card；若未獲使用者批准，狀態只能到 `ART_REVIEW`。
- [ ] 完成時提供前後對照、驗證層級、批次結果與下一個最小批次。

若任何舊文件或慣例與本憲法衝突，先停止擴大變更，向使用者指出衝突；除非使用者明確裁決，不得自行建立折衷的第三套流程。
