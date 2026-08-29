# 幻想鄉緣一計畫：Production Constitution

> 2026-08-29 使用者審定。細節規格以 `.claude/rules/` 與各 skill 為權威，本文件只留原則。

**目標**：最短時間做出玩家**看得見、走得到、可展示**的提升。
基線＝現行 `village.tscn` 地標區；20% 修舊／80% 新美術。內部整潔不算進度。

**紅線**

1. 先重用後新增；不建平行 pipeline 或第二套資料來源。
2. 沒有阻塞不重構核心；不順手擴張範圍、不過度工程。
3. 視覺只有使用者能批准（`ART_APPROVED`）；agent 至多 `ART_REVIEW`。
4. `godot/assets/blender/sources/` 唯讀。

**證據優先**

- 場景／節點／資源狀態：先用 godot-ai MCP 查實況，不讀檔名或文件推測。
  逾時不等於失敗——先 `editor_state` 確認再重試；同時只允許一個 AI 控編輯器。
- 結構驗證用 MCP 查詢；**視覺驗收才截圖**，一律 shotlist 固定機位。
  渲染問題（剔除、繞線、摩爾紋、光照）只有截圖抓得到。
- Skill 按需載入，一次一個 reference（路由見 CLAUDE.md 的 skill 清單）。

**流程**

- prototype → render → **Human Art Review** → rollout，不可跳步；未批准不得大量灌入。
- 日常改動跑 Fast 檢查（既有檢查，不重寫）；整合／世界生成變更才跑 Full regression。
- 三距離審：50m 量體 → 20m 街道節奏 → 5m 細節；不得用 5m 掩蓋 50m 失敗。

**行為**

- 已批准方向自主做到底，不要微批准；只在動地標、村莊結構、已核准美術方向、
  玩法／世界觀、或無回滾的破壞性操作前停下來問。
- 先給結論與證據，再說內部工作；方向有問題就以證據提更小更正確的替代方案。

---

# English Version

> User-ratified 2026-08-29. Detailed specs live in `.claude/rules/` and the
> project skills — those are authoritative; this document is principles only.

**Goal**: Deliver player-**visible, walkable, showable** improvements in the
shortest time. Baseline = the current `village.tscn` landmark area;
20% repair / 80% new art. Internal tidiness does not count as progress.

**Red lines**

1. Reuse before adding; never build a parallel pipeline or a second data source.
2. No core refactors unless actually blocked; no scope creep, no over-engineering.
3. Only the user approves visuals (`ART_APPROVED`); an agent reaches `ART_REVIEW` at most.
4. `godot/assets/blender/sources/` is read-only.

**Evidence first**

- Scene / node / resource state: query the godot-ai MCP for ground truth —
  never infer from filenames, docs, or memory. A timeout is not a failure:
  confirm via `editor_state`, then retry. Only one AI drives the editor at a time.
- Structural checks go through MCP queries; **screenshots are for visual
  acceptance only**, always from fixed shotlist cameras. Render-side defects
  (culling, winding, moiré, lighting) are catchable ONLY in screenshots.
- Load skills on demand, one reference at a time (routing: see the skill list in CLAUDE.md).

**Process**

- prototype → render → **Human Art Review** → rollout, no skipping; nothing
  unapproved gets mass-deployed.
- Day-to-day changes run Fast checks (existing checks, never rewritten);
  integration / world-generation changes run the Full regression.
- Three-distance review: 50m massing → 20m street rhythm → 5m detail;
  never use 5m detail to hide a 50m failure.

**Behavior**

- Once a direction is approved, execute autonomously to completion — no
  micro-approvals. Stop and ask only before: moving a major landmark, changing
  village structure, changing approved art direction, changing gameplay /
  worldbuilding, or any destructive action without a safe rollback.
- Lead with conclusions and evidence, then internals; if the direction is
  wrong, propose a smaller, more correct alternative backed by evidence.
