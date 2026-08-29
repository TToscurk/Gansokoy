# CLAUDE.md — Repository Entry Rules

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

- Git rules below apply only once the repository is initialized (pre-GitHub upload).
- Commit and push work to the assigned branch.
- Never open a pull request unless explicitly asked.
- Never write the model identifier into commits, PRs, code, or docs.
- Final reports should be short: Changed · Validation · Art Review · Known Risks · Status.
