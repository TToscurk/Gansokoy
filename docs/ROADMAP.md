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

**Phase 3 — Village Architecture Rollout, PILOT.** Blocks 209/210/214/215
built (18 houses, 7 module kinds village-wide), zero drift proven outside
the corridor, all five gates green. Awaiting Art Review.

## NEXT

- **Architecture Kit gap: a 9–10 m 総二階/大型町家 module** — required
  before full rollout; the village's back rows are 9.4/9.9 m and the kit
  tops out at 6.42 m.
- **Full rollout** to the remaining 36 blocks — only after the pilot clears
  Art Review and the back-row gap is closed.
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
