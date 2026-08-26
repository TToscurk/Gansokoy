# PROJECT STATE

Last updated: 2026-08-26.

This file is intentionally short. It contains only facts that should affect the next task. Load subsystem details only when that subsystem is being edited.

## Current Build

- Live game: **Godot 4.7** under `godot/` (`project.godot` features = 4.7; older docs saying 4.4 are historical).
- `src/` is the frozen three.js line.
- Human Village scene: `godot/maps/village/village.tscn` plus committed artifacts in `godot/maps/village/gen/`.
- This working copy is **not yet a git repository**; it will be initialized before upload to GitHub. Skip git status/branch checks until then, and do not treat their absence as an error.

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
