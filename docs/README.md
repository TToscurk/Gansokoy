# docs — Context Index

Keep task context small. Start with `PROJECT_STATE.md`, then load only the one subsystem document needed for the current task.

## Always-small context

| File | Purpose |
|---|---|
| `PROJECT_STATE.md` | Current canonical facts that affect the next task |
| `ROADMAP.md` | DONE / CURRENT / NEXT / LATER only |

Permanent agent policy lives in repo-root `.hermes.md` (the single authoritative instruction file; `CLAUDE.md` / `AGENTS.md` / `AGENT_CONSTITUTION.md` were removed 2026-09-09) and task-relevant `.claude/rules/` files.

## Load only when relevant

| Topic | File |
|---|---|
| Human Village rules (generator retired 2026-08-25; structure rules still apply) | `ningen-no-sato.md` |
| Human Village art direction | `village-art-direction.md` |
| Village rebuild concept (zones, river spec, machiya types) | `village-concept-reference.md` |
| Basin vista plan (DESIGN merged proposal, awaiting review) | `vista-basin-plan.md` |
| 新版人里規劃提案（DESIGN，等審查）：密度／水系四級／遠景視差實測 | `新人里規劃提案.md` |
| Generator domain vocabulary (village-generator ADRs superseded) | `domain-model.md` |
| Godot migration history (historical only — the `godot/blockout/` bake pipeline it documents no longer exists) | `godot-migration.md` |
| Border / horizon geography | `border-vistas.md` |
| 稗田邸 | `hieda-estate-features.md` |
| Yoriichi runtime | `yoriichi-runtime.md` |
| 序章主線 MQ00-MQ07、對話／任務／旗標系統 | `plans/2026-09-07-角色NPC任務UI規劃.md` |
| 隻狼式戰鬥（軀幹、彈反、敵人） | `plans/sekiro_combat_spec.md` |
| 博麗神社區域規格 | `HAKUREI_SHRINE_AREA_SPEC.md` |

## Archive rule

`docs/archive/` is historical evidence, not active context. Do **not** read it automatically.
Read archive files only when tracing an old decision, regression, or removed implementation.

Completed design diaries and obsolete state documents belong in `archive/`; current instructions must stay in the canonical files above.
