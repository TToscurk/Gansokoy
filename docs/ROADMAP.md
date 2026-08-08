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
| Phase 2 | Architecture Kit — 6 machiya modules |
| Project brain | `CLAUDE.md`, `.claude/rules/`, `PROJECT_STATE.md`, this file |

## CURRENT

Nothing in progress. Repository sits at the Phase 2 approved checkpoint.

## NEXT

Candidates awaiting a human decision. Neither is started.

- **Village rollout of the Architecture Kit** — distribution rule for 6
  modules over 169 houses + village regression.
- **Lighting / cel-shading round** — the parking lot for backlit plaster,
  water, blockout textures, prop scale.

## LATER

- Architecture Kit expansion: 入母屋 / 落棟 / 下屋 roofs.
- Hand-authored LOD0/1/2 (currently `lod_bias` only).
- Prop and villager asset pass (提灯, villagers, small props).
- 稗田邸 blockout material split (the only untextured building).
- Other 幻想鄉 locations beyond 人間之里 and 博麗神社.
