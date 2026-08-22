# docs — Context Index

Keep task context small. Start with `PROJECT_STATE.md`, then load only the one subsystem document needed for the current task.

## Always-small context

| File | Purpose |
|---|---|
| `PROJECT_STATE.md` | Current canonical facts that affect the next task |
| `ROADMAP.md` | DONE / CURRENT / NEXT / LATER only |

Permanent agent policy lives in repo-root `CLAUDE.md`, `AGENTS.md`, `AGENT_CONSTITUTION.md`, and task-relevant `.claude/rules/` files.

## Load only when relevant

| Topic | File |
|---|---|
| Human Village rules / pipeline | `ningen-no-sato.md` |
| Human Village art direction | `village-art-direction.md` |
| Machiya production kit | `machiya-production-kit.md` |
| Generator domain / ADR | `domain-model.md` |
| Godot environment / migration facts | `godot-migration.md` |
| Border / horizon geography | `border-vistas.md` |
| 稗田邸 | `hieda-estate-features.md` |
| Yoriichi runtime | `yoriichi-runtime.md` |

## Archive rule

`docs/archive/` is historical evidence, not active context. Do **not** read it automatically.
Read archive files only when tracing an old decision, regression, or removed implementation.

Completed design diaries and obsolete state documents belong in `archive/`; current instructions must stay in the canonical files above.
