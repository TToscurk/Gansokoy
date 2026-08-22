# CLAUDE.md — Repository Entry Rules

Project: 幻想鄉 / 博麗神社, a Godot 4.4 3D fan project. The live game is under `godot/`.
`src/` is the frozen three.js line and is not the default implementation target.

## Start Every Task

1. Read `AGENT_CONSTITUTION.md`.
2. Read `docs/PROJECT_STATE.md`.
3. Read only the `.claude/rules/` file(s) relevant to the task.
4. Read at most the one subsystem document needed for the task.
5. Inspect `git status`, `git diff`, and relevant code before expanding context.

Do **not** automatically read all of `docs/`, `docs/archive/`, old review notes, or unrelated subsystem files.
`docs/archive/` is historical evidence only; read it only when a past decision is disputed.

## Working Rules

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
| Machiya production kit | `docs/machiya-production-kit.md` |
| Generator domain / ADR | `docs/domain-model.md` |
| Godot environment | `docs/godot-migration.md` |
| Map horizons / geography | `docs/border-vistas.md` |
| 稗田邸 | `docs/hieda-estate-features.md` |
| Yoriichi runtime | `docs/yoriichi-runtime.md` |

`docs/README.md` is the document index.

## Git / Reporting

- Commit and push work to the assigned branch.
- Never open a pull request unless explicitly asked.
- Never write the model identifier into commits, PRs, code, or docs.
- Final reports should be short: Changed · Validation · Art Review · Known Risks · Status.
