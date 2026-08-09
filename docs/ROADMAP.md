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
| Phase 3 pilot / 3.1A / 3.1B / 3.2A | north-gate corridor kit rollout, street section, fire-watch crossing, sight-line diagnostic |
| Architecture Consolidation | legacy house removal — 170/170 production, 0 blockout |
| Main Street batch | 本通 frontage restored: 塀/門/鳥居/蔵/幟/街路樹, N2 lean-to, 溝蓋, 辻行灯 |
| Vegetation production pass | village-local readable canopies; activity-sparse core and entrances; clustered, denser village-edge ground layers; fixed 5-camera local review loop |
| Project brain | `CLAUDE.md`, `.claude/rules/`, `PROJECT_STATE.md`, this file |

## CURRENT

**Human Village vegetation production pass complete.** Five fixed local-render
views confirm readable tree crowns, clustered ground vegetation, sparse human
activity zones, denser village edges, and clear roads/entrances/market/shrine.
Full static suite green. Awaiting Art Review.

## NEXT

- **Lighting / cel-shading round** — the street lamps now carry the village
  vocabulary; their light behaviour is untouched and waits for this round.
- **稗田邸 blockout material split** and **tower asset quality**
  (`tower_bell` / `tower_fire`) — the remaining non-residential blockout.
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
