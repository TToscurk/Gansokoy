# PROJECT STATE

Last updated: 2026-08-26.

This file is intentionally short. It contains only facts that should affect the next task. Load subsystem details only when that subsystem is being edited.

## Current Build

- Live game: **Godot 4.7** under `godot/` (`project.godot` features = 4.7; older docs saying 4.4 are historical).
- `src/` is the frozen three.js line.
- Human Village scene: `godot/maps/village/village.tscn` plus committed artifacts in `godot/maps/village/gen/`.
- Git repository initialized (branch `main`); not yet pushed to GitHub. Commit each approved round before handing work to another agent.

## Human Village — new baseline (user ruling 2026-08-26)

- The 170-house era is **fully retired and deleted (2026-08-25)** — generator pipeline (`gen_town.gd`, `tools/town/`, `make_town.py`, `make_machiya.py`, `town_modules.json`) **and the machiya assets, market, village gates, and portals**. None of these exist in the repo. Do not look for them, restore them, or treat docs describing them as current.
- **The current `village.tscn` IS the new baseline** (user ruling): landmarks 鎮守之杜, 稗田邸(+後院), 鈴奈庵, 寺子屋, 霧雨店, 鯢吞亭, 龍神像; 14 路燈; vegetation; vista; terrain; boundary. ~221 nodes. Future village content builds on top of this.
- The village is a **frozen, committed scene**: edit `village.tscn` / its `gen/` artifacts directly, following normal art-review gates.
- Remaining live generators: `gen_hieda*.gd`, `gen_kourindou.gd`, `gen_trail.gd`, `gen_textures.gd`, `gen_charpreview.gd` + Blender `make_hieda/shourou/trees/props/hedge/chars.py`.
- Known naming wart: scene nodes and `gen/` folder use 「裨田邸」 (typo) for 稗田邸. Renaming touches scene references — leave as-is unless a task explicitly fixes it.
- Visual changes still require prototype → render → Human Art Review → rollout.
- Next major art direction is lighting / cel-shading.

## Yoriichi

- The old procedural Y02 rebuild track is obsolete and must not be treated as the active character workflow.
- Active character prefab: `角色/緣一動作/yoriichi_character_meshy_full.tscn`.
- Body and Haori use the same 24-bone Meshy skeleton.
- Runtime locomotion, draw/sheathe, attacks, dodge/roll, jump/fall/land, sword sockets, and the current AnimationTree controller have been implemented and validated at the character-project level.
- Yoriichi has **not yet replaced the formal Player in the main `godot/` game project**.
- Read `docs/yoriichi-runtime.md` only when working on Yoriichi.

## Village Rebuild — active work (2026-08-26)

- Visual authority for the rebuild: `docs/village-concept-reference.md` (user-supplied concept art: dragon plaza center, market axis south, residential west, Hieda estate + rice fields east, graveyard north, **wide open-U river along the south edge**).
- River rework in progress on `maps/slice/slice.tscn`: ring/narrow versions v1–v5 were **rejected by the user (too narrow, not U-shaped)**; current candidate is `river_open_u` v6b (`shots2/river_open_u_v6b_*_20260826`), awaiting Human Art Review.
- River art card (user, 2026-08-26): **deep moat-like channel, stone-textured revetment, vegetation + trees along the banks**. The procedurally generated bridge is **placeholder only — do not treat it as final**; the user will replace it with a Meshy-made bridge.
- v7 pass applied on slice (2026-08-26 afternoon): 22 bank trees (round/pine/sakura mix at the three bridge areas, node `RiverV3_Candidate/RiverBankTrees`), stone revetment materials assigned (`river_ishigaki_dry.tres` on Dry banks, `river_ishigaki_wet.tres` on Wet banks; shared `2F岸石.tres` untouched). Shots: `shots2/river_open_u_v7*_20260826`.
- Bank trees were removed again on user order (2026-08-26 evening): trees/vegetation will come from Meshy; do not plant the existing tree_* GLBs along the river.
- A GPT repair attempt (2026-08-26, `repair_river_outer_transition.gd`, mesh swaps on Vista/OuterTerrainTransition, hidden vista trees) was **rejected by the user and fully reverted**; it is archived in `work_backups/gpt_river_attempt_20260826/` and is NOT part of the current scene.
- Second defect found the same way: `VillageLandExtension`, `EastTail/WestTailLandConnection`, `OuterTerrainTransition` shipped with **no material at all** (rendered white). Patched: earth on the extensions/tails, grass on the transition.
- Water is CLEAN — probe audit confirms `RiverWater` covers only the channel; earlier oversized-water suspicion was wrong.
- Materials ready: `river_ishigaki_dry.tres` / `river_ishigaki_wet.tres` (stone revetment, triplanar) and `river_transition_grass.tres` (double-sided matte grass) in `assets/materials/`. Audit tool kept at `godot/tools/audit_river_slice.gd`. The large arch visible at the east edge belongs to the pre-existing root `Vista` mesh, not the river banks; an A/B hide test exposed world void, so `Vista` remains unchanged pending a dedicated landscape-vista replacement.
- **v9 landscape pass (2026-08-26 night)**: continuous ground achieved — `GroundUnderlay` node (generated by `tools/gen_ground_underlay.gd`, 5m grid sampled 0.22m under every ground mesh, dips below the river bed inside the channel) fills all sky-holes between Terrain / VillageLandExtension / OuterTerrainTransition / hills. Fog fixed: `fog_density` 0.0016→0.0006, `volumetric_fog_density` 0.012→0.004, `volumetric_fog_sky_affect` 0.18→0 (this was the blocky-sky cause — froxel grid compositing onto the sky, not the cumulus shader). Evidence: `shots2/slice_v9c_fine_20260826`. GPT's rejected repair attempt archived in `work_backups/gpt_river_attempt_20260826/`.
- Next: user will apply zone material transitions on the ground for lived-in feel; vegetation/bridges via Meshy.
- Remaining polish for next round: bright band at the revetment top edge along the waterline (stone material washes pale under fog at distance) — tune stone tint/fog, or accept until lighting pass.
- Do not integrate any river into `village.tscn` until the slice prototype is approved.

## Asset Pipeline — user ruling 2026-08-26

- **LLM-written procedural 3D asset generation (bpy code producing props/buildings) is REJECTED for new visible assets** — quality verdict: too ugly. New visible 3D assets come from the **image-AI → Meshy 7** workflow (image concept → Meshy image-to-3D → Godot import), same lineage as the Yoriichi character and `godot/imported_models/`.
- Procedural generation remains acceptable only for non-asset scene work: terrain shaping, water surfaces, scattering/placement, and utility geometry.
- Existing baked assets in the current baseline stay as-is until individually replaced.

## Current Priorities

1. Keep the working copy clean and avoid reviving obsolete prototype/review workflows or the retired village generator.
2. Continue Human Village lighting / cel-shading and remaining visible art-quality work.
3. Integrate the finished Yoriichi runtime into the formal game Player only when that task is explicitly started.

## Do Not Reopen Without Evidence

- Current `village.tscn` landmark placement (the new baseline).
- The 2026-08-25 retirement of the 170-house era (generator AND assets) and the 2026-08-26 new-baseline ruling.
- Godot front-face winding convention.

## Context Rule

Do not load `docs/archive/` by default. Historical documents are for archaeology only, not current instructions.
