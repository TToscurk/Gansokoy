---
name: blender-asset-production
description: Produce or substantially revise reusable Blender-to-GLB assets for this repository, including trees, props, facades, buildings, and landmarks. Use when asset identity, mesh geometry, silhouette, construction, or reusable asset families must change and the result must be exported, imported, and reviewed in Godot.
---

# Blender Asset Production

> **⚠️ Scope narrowed (user ruling 2026-08-26):** LLM-written procedural
> generation of new visible 3D assets (props, buildings, bridges) is
> **rejected — too ugly**. New visible assets come from the image-AI → Meshy 7
> workflow instead. Use this skill only for: maintaining existing generators,
> terrain/water/utility geometry, scattering, and export/import mechanics of
> Meshy-produced GLBs. Do not author new bpy asset generators for visible art.

Read `CLAUDE.md`, `.claude/rules/art-review.md`, and `.claude/rules/godot.md`. Inspect the relevant source in `godot/assets/blender/` before editing; reuse its helpers, export conventions, materials, and output paths.

## Workflow

1. Inspect the current Blender generator/source and its generated GLB. Establish gameplay scale, origin, orientation, material surfaces, and collision or placement contracts.
2. Modify or create reusable production source. Prefer a small coherent family over hand-placed one-off geometry.
3. Make geometry or composition genuinely differ where identity requires it. Scaling, rotation, recolouring, or renaming alone are not asset variation.
4. Run the existing generator in Blender batch mode, normally:
   `D:\Blender\blender.exe -b -P godot/assets/blender/<script>.py -- <existing-output-args>`
   Follow the script's actual argument contract; do not rewrite the pipeline without necessity.
5. Verify each GLB exists and inspect useful measures such as dimensions, face count, surface count, and file size against expected values.
6. Run Godot import with `godot --headless --path godot --import` (resolve the executable the way `tools\capture-godot.ps1` does — glob `D:\Godot*\Godot*.exe`; do not hard-code one install path), then verify the new asset loads through the existing scene or generator path.
7. Render it in Godot with `tools\capture-godot.cmd`, inspect the images, and compare fixed-camera BEFORE and AFTER evidence.
8. Allow at most one targeted visual correction round. Re-export, re-import, and re-render after that correction.
9. Run validations relevant to the affected map and collision contract.
10. **Stop at `ART_REVIEW`.** Present the render evidence and wait for Human Art Review before any rollout or batch replacement (AGENT_CONSTITUTION 紅線 6).

Preserve gameplay scale, origins, collision/OBB constraints, and shared material strategy. Avoid needless unique materials, pipeline rewrites, and regeneration of unrelated assets.
