# 幻想鄉緣一計畫：Production Constitution

> 2026-08-29 使用者審定。細節規格以 `.claude/rules/` 與各 skill 為權威，本文件只留原則。

**目標**：最短時間做出玩家**看得見、走得到、可展示**的提升。
基線＝現行 `village.tscn` 地標區；20% 修舊／80% 新美術。內部整潔不算進度。

**紅線**

1. 先重用後新增；不建平行 pipeline 或第二套資料來源。
2. 沒有阻塞不重構核心；不順手擴張範圍、不過度工程。
3. 視覺只有使用者能批准（`ART_APPROVED`）；agent 至多 `ART_REVIEW`。
4. `godot/assets/blender/sources/` 唯讀。

**證據優先 — Godot MCP 政策**

每個 Godot 任務開始時，先確認 godot-ai MCP 工具是否可用。

- 可用時，**必須**以 MCP 為場景檢查、除錯、編輯、驗證的主要手段。
- 不可用時，**必須先明確回報這個事實**，才可改用替代方法。
- **不得**以截圖作為主要除錯手段。
- 當 MCP 能提供場景、節點、transform、mesh、材質、碰撞或資源資訊時，
  **不得**反覆執行專案再看截圖。
- 截圖只可用於**最終視覺驗收**，或問題本質為視覺、無法用 MCP 可靠檢查時。
- 為除錯而截圖前，先用 MCP 檢查相關場景結構與屬性。
- 當 MCP 能取得實際數值時，**絕不**僅憑截圖推斷節點位置、尺寸、場景階層、
  幾何或碰撞；同樣不得從檔名或文件推測。

除錯順序，不可跳步：

```
MCP 檢查 → 程式碼／資源檢查 → 找出根因 → 修正 → MCP 驗證 → （選用）截圖驗收
```

- 逾時不等於失敗——先 `editor_state` 確認再重試；同時只允許一個 AI 控編輯器。
- 截圖一律用 shotlist 固定機位。渲染問題（剔除、繞線、摩爾紋、光照）只有截圖抓得到，
  這是截圖不可取代的唯一場合。
- Skill 按需載入，一次一個 reference（路由表見 `CLAUDE.md` §Project Skill Discovery）。

**流程**

- 製作場景內的地形、或做村落／區域規劃前，先參考概念圖 `docs/reference/人間之里概念圖/`：
  以 **`村落農村概念俯視.png` 為主要依據**（搭配 `村落農村概念俯視區域分隔.png` 看分區），
  其餘（住商、住宅、高空俯視、河童重工）為輔助參考。
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

**Evidence first — Godot MCP policy**

At the beginning of every Godot task, verify whether the godot-ai MCP tools
are available.

- If available, you **MUST** use Godot MCP as the primary method for scene
  inspection, debugging, editing, and validation.
- If unavailable, **explicitly report that fact** before using any fallback method.
- **DO NOT** use screenshots as the primary debugging method.
- **DO NOT** repeatedly run the project and inspect screenshots when MCP can
  provide the relevant scene, node, transform, mesh, material, collision, or
  resource information.
- Screenshots may only be used for **final visual verification**, or when the
  problem is inherently visual and cannot be reliably inspected through MCP.
- Before taking a screenshot for debugging, first inspect the relevant scene
  structure and properties through MCP.
- **Never** infer node positions, dimensions, scene hierarchy, geometry, or
  collision solely from screenshots when MCP can provide the actual values —
  and never infer them from filenames, docs, or memory either.

Required debugging order, no skipping:

```
MCP inspection → code/resource inspection → root cause → fix
  → MCP validation → optional screenshot verification
```

- A timeout is not a failure: confirm via `editor_state`, then retry. Only one
  AI drives the editor at a time.
- Screenshots always come from fixed shotlist cameras. Render-side defects
  (culling, winding, moiré, lighting) are catchable ONLY in screenshots — that
  is the one job screenshots cannot delegate to MCP.
- Load skills on demand, one reference at a time (routing table: `CLAUDE.md` § Project Skill Discovery).

**Process**

- Before building in-scene terrain or planning village/area layout, first review
  the concept art in `docs/reference/人間之里概念圖/`. **`村落農村概念俯視.png`
  (village-farm top view) is the primary authority** (use
  `村落農村概念俯視區域分隔.png` for its zoning breakdown); the other sheets
  (residential/commercial, housing, high-altitude view, Kappa industry) are
  supporting references.
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
