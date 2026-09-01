# CLAUDE.md — Repository Entry Rules

## 憲法紅線（不可跳過 · 本節即是規則本體，不是指路）

> 這幾條直接寫在此處，因為只有 `AGENTS.md` / `CLAUDE.md` 會被自動注入 context。
> 完整原則與流程見 `AGENT_CONSTITUTION.md`（使用者 2026-08-29 審定），衝突時以憲法為準。

1. **先重用後新增**：不建平行 pipeline、不建第二套資料來源。
2. **無阻塞不重構核心**：不順手擴張範圍、不過度工程。
3. **視覺只有使用者能批准**（`ART_APPROVED`）；agent 至多推進到 `ART_REVIEW` 就停。
4. `godot/assets/blender/sources/` **唯讀**。
5. **證據優先**：場景／節點／資源狀態一律先用 godot-ai MCP 查實況（`editor_state` 起手），
   不從檔名、文件或記憶推測。逾時 ≠ 失敗，確認後重試；同時只准一個 AI 控編輯器。
6. **每一次**觸及 Godot 的修改（場景／節點／資源、GDScript、生成器、匯入、material／shader、
   驗證腳本）動手前，都要先載入 `godot-master` skill 並依其路由讀該次工作對應的**單一** reference。
   同一輪對話先前載入過**不構成豁免**。不得憑記憶寫 Godot 4.7 API。
7. **概念圖是權威，文字轉錄不是**：村落／地形規劃基準＝
   `docs/reference/人間之里概念圖/村落農村概念俯視.png`。`docs/village-concept-reference.md`
   只是索引，不得用其字句否定圖上內容；該資料夾內不存在的圖＝已作廢，不得引用。
8. **流程不可跳步**：prototype → render → Human Art Review → rollout；未批准不得大量灌入。
   三距離審：50m 量體 → 20m 街道節奏 → 5m 細節，不得用 5m 細節掩蓋 50m 失敗。
9. **停下來問**的唯一時機：動地標、改村莊結構、改已核准美術方向、改玩法／世界觀、
   或無安全回滾的破壞性操作。其餘已批准方向自主做到底，不要微批准。

---

Project: 幻想鄉 / 博麗神社, a Godot 4.7 3D fan project. The live game is under `godot/`.
`src/` is the frozen three.js line and is not the default implementation target.
The 170-house village generator pipeline was retired 2026-08-25; the village is a frozen committed scene.

## Start Every Task

1. Read `AGENT_CONSTITUTION.md` (使用者審定精簡版，含 MCP 證據優先政策).
2. 涉及 Godot 場景/節點/資源狀態：用 godot-ai MCP 查實況（`editor_state` 起手），不推測。
3. Read `docs/PROJECT_STATE.md`、相關 `.claude/rules/` 檔，與至多一份子系統文件。
4. Inspect `git status`, `git diff`, and relevant code before expanding context.
   (Git is initialized on branch `main`, local only — not yet pushed to GitHub.
   Commit each approved round before handing work to another agent.)

Do **not** automatically read all of `docs/`, `docs/archive/`, old review notes, or unrelated subsystem files.
`docs/archive/` is historical evidence only; read it only when a past decision is disputed.

## Project Skill Discovery

The canonical project skills live in `.claude/skills/` (real files; `.agents/skills/` is a junction mirror for Codex so the two never drift). Load skills **on demand, not as a ritual** — routing table in `AGENT_CONSTITUTION.md` §3.

## Working Rules

- Subagents for scan/inventory/audit work default to the **haiku** model, and their
  task prompt must name an explicit whitelist of files or directories to read —
  never "scan everything". Repo-wide deep scans are one-off; their conclusions live
  in `docs/PROJECT_STATE.md` and are not re-run.
- Work only on the requested deliverable; no opportunistic repo-wide refactors.
- Preserve approved production baselines and validated pipelines.
- Ask before destructive changes with no safe rollback, changing village/road structure, moving major landmarks, changing approved art direction, or changing gameplay/worldbuilding.
- Visual work follows: prototype/slice → render → Human Art Review → rollout.
- Prefer targeted reads and targeted edits over broad audits.
- Update documentation only when the canonical state actually changed.

## Canonical Context Map

| Need | Read |
|---|---|
| Current state | `docs/PROJECT_STATE.md` |
| Next priorities | `docs/ROADMAP.md` |
| Human Village rules | `docs/ningen-no-sato.md` |
| Village art direction | `docs/village-art-direction.md` |
| Generator domain / ADR | `docs/domain-model.md` |
| Godot environment | `docs/godot-migration.md` |
| Map horizons / geography | `docs/border-vistas.md` |
| 稗田邸 | `docs/hieda-estate-features.md` |
| Yoriichi runtime | `docs/yoriichi-runtime.md` |

`docs/README.md` is the document index.

## Git / Reporting

- **This repo uses Git LFS for binary assets.** After any clone or machine move, run
  `git lfs pull` (or `git lfs checkout` if objects are already local) BEFORE opening
  the project in Godot. Opening with un-smudged LFS pointers makes every texture/GLB
  import fail and stamps sticky `valid=false` into the `.import` files — recovery
  then requires stripping those flags and a full headless reimport (2026-08-29 incident).
- Git rules below apply only once the repository is initialized (pre-GitHub upload).
- Commit and push work to the assigned branch.
- Never open a pull request unless explicitly asked.
- Never write the model identifier into commits, PRs, code, or docs.
- Final reports should be short: Changed · Validation · Art Review · Known Risks · Status.
