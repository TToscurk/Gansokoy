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
