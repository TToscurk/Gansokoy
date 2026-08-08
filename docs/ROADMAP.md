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

**Phase 3.2A — 本通 sight-line, diagnostic increment.** Three civic nodes
(共同井戸 / 上屋 / 常夜灯の対) built and awaiting Art Review. Result is a
*negative* one and that is the point: off-axis nodes fill the mid-field
(z=−60 FOV median 114→75 m) but barely move the axis (北門 axis ±8°
unchanged at 78.8 m). Zero drift proven at byte level — all 54 `gen/*.res`
and both data JSONs unchanged; 0 nodes moved. All five gates green.

Next after review: **Phase 3.2B** — reopen landmark frontage placement on
本通 (the only mass that can break the axis is a building facing it), then
full rollout (still blocked on the 9–10 m back-row module gap).

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
