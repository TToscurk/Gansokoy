# Haori Physics Experiment Archive

The production Yoriichi prefab no longer references any independent-Haori,
SpringBone, SoftBody, cloth-proxy, or anti-clipping experiment.

The research assets are intentionally preserved at their original paths so
their internal `res://` references and existing local edits are not damaged.
This file is the archive index; it does not make any experiment part of the
runtime dependency graph.

Archived research groups:

- `res://yoriichi_character_v21.tscn`
- `res://haori_v21_character.tscn`
- `res://haori_v21_rigged.glb`
- `res://haori_v21_anchor.gd`
- `res://haori_v21_setup.gd`
- `res://haori_v21_runner.gd` and `res://haori_v21_runner.tscn`
- `res://yoriichi_character_v2_haori_test.tscn`
- `res://yoriichi_haori_v2_aligned.glb`
- `res://yoriichi_haori_v2_rigged.glb`
- `res://haori_follow.gd`
- `res://haori_ab_runner.*`, `res://haori_anim_runner.*`, and
  `res://haori_full_runner.*`
- `res://haori_softbody_runner.*`, `res://softbody_diag.*`, and
  `res://softbody_min_test.*`
- `res://haori_softbody_proxy.glb` and `res://yoriichi_softbody_body.fbx`
- `res://anti_clip/`
- `角色/haori_work/` Blender checkpoints, reports, and render evidence

Production entry points:

- `res://yoriichi_character_meshy_full.tscn`
- `res://yoriichi_test_level.tscn`

Neither production entry point may reference the archived groups above.
