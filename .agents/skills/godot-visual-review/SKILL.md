---
name: godot-visual-review
description: Run the mandatory in-engine visual feedback loop for Godot 3D art, environment, architecture, material, dressing, composition, or asset changes in this repository. Use whenever success includes how a Godot scene looks, including requests for visual polish, before/after review, screenshot comparison, or fixed-camera acceptance.
---

# Godot Visual Review

Treat rendered images as required evidence. Read `CLAUDE.md`, `.claude/rules/art-review.md`, `.claude/rules/execution-modes.md`, and `.claude/rules/godot.md` before acting.

## Workflow

1. Find the existing shotlist for the map under `godot/tools/shots/` (or the path named by the task). Do not alter cameras between comparisons.
2. Capture BEFORE on Windows with:
   `tools\capture-godot.cmd -Map <map> -Shotlist <shotlist> -OutputDirectory <before-dir>`
3. Inspect every relevant PNG. Record concrete repetition, clipping, scale, hierarchy, sightline, composition, or readability problems.
4. Implement one meaningful, scoped visual batch. Preserve unrelated systems and protected invariants.
5. Capture AFTER with the exact same map, shotlist, camera transforms, time, and renderer.
6. Inspect every relevant AFTER image and compare it directly with BEFORE. Never infer visual success from code, parameters, statistics, or static checks.
7. If an obvious scoped defect remains, perform one targeted correction and capture the same views once more. Stop after that correction round; report remaining weaknesses honestly.
8. Run the relevant repository validation tools, commonly `godot/tools/check_map.gd`, `walk_test.gd`, `lm_ghost.gd`, `portal_test.gd`, and `hieda_boundary_check.gd`.
9. **Stop at `ART_REVIEW`.** Present the BEFORE/AFTER evidence and wait for Human Art Review. Never declare visual work complete or approved on your own judgement (AGENT_CONSTITUTION 紅線 6); rollout happens only after explicit user approval.

Use the existing capture wrapper; do not invent another screenshot system. Do not expand into lighting, gameplay, NPCs, vegetation, or another subsystem unless explicitly included.

## What screenshots cannot settle

Screenshots prove *rendering* (culling, winding, moiré, lighting, composition). They do **not** settle geometry, and vision judgement of a small or low-resolution model is actively misleading — asked to describe a single 300px asset it will confidently return the wrong object.

Before placing any GLB, and again after placing it, settle these with numbers:

| Question | Wrong tool | Right tool |
|---|---|---|
| Where is the origin? | assume geometric centre | `godot/tools/asset_probe.py` |
| How high is the walkable surface? | AABB height | `asset_probe.py --profile` |
| Which way does a slope fall? | AABB corners | the node's `basis`, not its bounds |
| Did it land on the ground? | eyeball the render | `model_bottom + y × scale == surface` |

`asset_probe.py` talks to Blender over MCP and reads GLB vertices directly (it scans ports 9875-9880; the addon panel often reports a different port than it listens on).

Two traps this repo has already hit:

- **Origins are usually centred, but not always.** Every riverbank/landscape GLB measured so far is centred except `盆樹.glb`, whose origin is at its base. Placing it as if centred left it floating.
- **AABB height ≠ walkable rise.** `降台石5段.glb` has an AABB of 0.85m but only 0.59m of actual step rise; the remainder is base hollow and a top ridge. Sizing `scale` from the AABB made it miss both the bank top and the platform.

Also beware double-applying `scale`: viewport-reported AABB sizes are already scaled, so `aabb_size * scale` counts it twice.
