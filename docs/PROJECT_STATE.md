# PROJECT STATE

Last updated: 2026-08-22.

This file is intentionally short. It contains only facts that should affect the next task. Load subsystem details only when that subsystem is being edited.

## Current Build

- Live game: Godot 4.4 under `godot/`.
- `src/` is the frozen three.js line.
- Human Village scene: `godot/maps/village/village.tscn`.
- Human Village generator entry: `godot/tools/gen_town.gd`.
- Village roads, river, major landmarks, portals, production housing baseline, and deterministic generation are locked unless explicitly reopened.

## Human Village

- Production architecture is the active residential baseline; legacy residential blockout is no longer the target.
- Main street, market, vegetation, facade dressing, and major landmarks have production passes in place.
- Visual changes still require prototype/slice → render → Human Art Review → rollout.
- Next major art direction is lighting / cel-shading, with remaining quality debt around selected landmarks, close-range props, and LOD.

## Yoriichi

- The old procedural Y02 rebuild track is obsolete and must not be treated as the active character workflow.
- Active character prefab: `角色/緣一動作/yoriichi_character_meshy_full.tscn`.
- Body and Haori use the same 24-bone Meshy skeleton.
- Runtime locomotion, draw/sheathe, attacks, dodge/roll, jump/fall/land, sword sockets, and the current AnimationTree controller have been implemented and validated at the character-project level.
- Yoriichi has **not yet replaced the formal Player in the main `godot/` game project**.
- Read `docs/yoriichi-runtime.md` only when working on Yoriichi.

## Current Priorities

1. Keep `main` clean and avoid reviving obsolete prototype/review workflows.
2. Continue Human Village lighting / cel-shading and remaining visible art-quality work.
3. Integrate the finished Yoriichi runtime into the formal game Player only when that task is explicitly started.

## Known Traps

- Face winding is only provable in-engine. Blender renders double-sided, Godot culls back faces — the roof winding bug survived months of static gates and Blender renders while every house was see-through in-game. A new plane needs an in-engine screenshot or a normal assertion.
- Per-layer RNG isolation is required. Inserting a random draw into an existing stream shifts every downstream placement; add a new seeded stream instead.
- `bamboo`, `eientei`, `namelessHill`, `shrine`, `sunflower` have no Godot scene. They need `node tools/export-godot.mjs` to bake `godot/blockout/*.glb`, which is gitignored — `mapRegistry.json` marks them `built: true` regardless.

## Do Not Reopen Without Evidence

- Human Village road/river structure and major landmark placement.
- Approved machiya proportions, material language, and production asset pipeline.
- `make_town.py` as the writer for `town_modules.json`.
- `gen_town.gd` ownership of shared generation state / deterministic RNG.
- Godot front-face winding convention.

## Context Rule

Do not load `docs/archive/` by default. Historical documents are for archaeology only, not current instructions.
