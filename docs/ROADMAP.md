# ROADMAP

Status only. No implementation detail — that lives in the subsystem docs.
For "where are we right now", read `docs/PROJECT_STATE.md`.

---

## DONE

| | |
|---|---|
| three.js 博麗神社 (`src/`) | frozen line, not maintained |
| Godot migration | `godot/` is the live build |
| 人間之里 block restructure | Stages 1–4, 169 houses, roads, river, revetments |
| Landmark migration | 6 landmarks with real content + 3 towers + 3 bridges |
| 稗田邸 exterior | full standalone design placed in the village map |
| 稗田邸 interiors | 1F 玄関/客間 · 2F 阿求書房 · 3F 大書庫, portals linked |
| Phase 1 | `machiya_f_a` production prototype + semantic material pipeline |
| Phase 1.1 | proportion & roof language rebalance |
| Phase 1.5 | vertical slice art benchmark (`maps/slice/`) |
| Phase 1.6 | legacy blockout quarantine in the slice |
| Phase 1.7 | material readability pass |
| Phase 2 | Architecture Kit — 6 machiya modules (structural baseline) |
| Phase 2.5 | facade & life dressing — 3 hero storefronts, business identity by composition |
| Phase 2.6 / 2.6b | foreground prop v2, cloth as cloth, vertical dressing, cloth clearance from eave planes |
| Project brain | `CLAUDE.md`, `.claude/rules/`, `PROJECT_STATE.md`, this file |

## CURRENT

**Phase 3 Architecture Consolidation — Legacy House Removal.** Composition
work is paused by human instruction. Three new production modules built
(`machiya_e_p` / `machiya_n_a` / `machiya_n_o`) and swapped in inside the
north-gate corridor, which is now 18/18 production. Village-wide 64/170 (38%)
production. Awaiting Art Review on the modules; rollout is one flag flip.

## NEXT

- **Village-wide rollout** of the consolidation — `CONSOLIDATE_ALL = true`
  plus routing `machiya_f_b`'s 32 lots through `_kit_pick` (no new module
  needed; fw 10.74 sits between `f_n` 9.96 and `f_o` 11.76).
- **Phase 3.2B — landmark frontage on 本通** — deliberately *after* the
  legacy removal: a building that stops the axis must not itself be a
  blockout.
- **Lighting / cel-shading round** — after the village carries production
  architecture, not before (Phase 1.6's lesson: you cannot art-review a
  scene dominated by blockout).

## LATER

- Architecture Kit expansion: 入母屋 / 落棟 / 下屋 roofs.
- Hand-authored LOD0/1/2 (currently `lod_bias` only).
- Prop and villager asset pass (提灯, villagers, small props).
- 稗田邸 blockout material split (the only untextured building).
- Other 幻想鄉 locations beyond 人間之里 and 博麗神社.
- **AI 3D asset pipeline** — deferred by human decision. Audit found no GPU
  on this machine and all model-weight hosts blocked by egress policy; not
  actionable here without human intervention.
