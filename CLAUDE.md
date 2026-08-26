# CLAUDE.md — Repository Entry Rules

Project: 幻想鄉 / 博麗神社, a Godot 4.7 3D fan project. The live game is under `godot/`.
`src/` is the frozen three.js line and is not the default implementation target.
The 170-house village generator pipeline was retired 2026-08-25; the village is a frozen committed scene.

## Start Every Task

1. Read `AGENT_CONSTITUTION.md`.
2. Read `docs/PROJECT_STATE.md`.
3. Read only the `.claude/rules/` file(s) relevant to the task.
4. Read at most the one subsystem document needed for the task.
5. Inspect `git status`, `git diff`, and relevant code before expanding context.
   (This working copy has no git yet — it will be initialized before GitHub upload.
   Until then skip git checks and git-dependent skills; this is not an error.)

Do **not** automatically read all of `docs/`, `docs/archive/`, old review notes, or unrelated subsystem files.
`docs/archive/` is historical evidence only; read it only when a past decision is disputed.

## Project Skill Discovery

The canonical project skills are shared from `.agents/skills/` to avoid duplicate
Codex/Claude copies drifting apart. For Godot work, load
`.agents/skills/godot-master/SKILL.md`; for scene design, road planning, 3D
layout, blockout, sightlines, landmark guidance, or level flow, also load
`.agents/skills/level-design/SKILL.md`. Follow the on-demand routing and
precedence rules in `AGENT_CONSTITUTION.md` under "Godot Skill 路由規則".

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
