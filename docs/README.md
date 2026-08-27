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
| Human Village rules (generator retired 2026-08-25; structure rules still apply) | `ningen-no-sato.md` |
| Human Village art direction | `village-art-direction.md` |
| Village rebuild concept (zones, river spec, machiya types) | `village-concept-reference.md` |
| Basin vista plan (4-layer parallax, hill ring, Meshy anchors) | `vista-basin-plan.md` |
| Vista basin redesign proposal (DESIGN, awaiting review) | `vista-basin-plan.md` |
| Generator domain vocabulary (village-generator ADRs superseded) | `domain-model.md` |
| Godot migration history (historical; current version is 4.7) | `godot-migration.md` |
| Border / horizon geography | `border-vistas.md` |
| 稗田邸 | `hieda-estate-features.md` |
| Yoriichi runtime | `yoriichi-runtime.md` |

## Archive rule

`docs/archive/` is historical evidence, not active context. Do **not** read it automatically.
Read archive files only when tracing an old decision, regression, or removed implementation.

Completed design diaries and obsolete state documents belong in `archive/`; current instructions must stay in the canonical files above.
