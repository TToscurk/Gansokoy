# Rule: Godot Generation, Import & Scene Validation

Environment facts: `docs/godot-migration.md`. Village facts and pipeline:
`docs/ningen-no-sato.md`. This file is the short list of traps.

## Winding

**Front face = clockwise.** Godot culls back faces; Blender/Cycles renders
double-sided. A mis-wound surface looks correct in a Blender render and is
invisible in-engine. Cost so far: an entire 6 m sando that rendered
perfectly and did not exist in the game.

## glTF import cache does not auto-refresh

When a module's **material structure** changes (surface count, material
names), Godot keeps the stale import. Required sequence:

```
rm godot/.godot/imported/<name>.glb-*
godot --headless --path godot --import
```

Symptom if skipped: `semantic_mesh()` returns 1 surface for a 6-material
mesh.

## Generators

- Headless SceneTree scripts:
  `godot --headless --path godot --script tools/<gen>.gd`
- `gen_lib.gd` is the shared library (`box/cyl/strut/pbr/flat_mat/
  prop_mesh/tree_mesh/blob_mesh/tuft_mesh/make_multimesh/terrain/boundary/
  pond_water/pond_carve/vista/semantic_mesh`). Add primitives there, not
  in individual generators.
- `pbr()` uses triplanar UVs: `uv1_scale` multiplies world position, so
  **larger number = finer texture**, tile edge = 1 / uv.
- Per-layer RNG isolation. Changing draw counts inside a shared RNG stream
  shifts everything downstream — prove zero drift by diffing node name +
  transform multisets per group.
- Collision: trimesh only from `needs_trimesh` meta with
  `TRIMESH_MIN_SPAN = 15`. MultiMesh instances get box colliders, never
  trimesh.
- Type annotations are required where GDScript cannot infer
  (`var x: Vector3 = ...`); the parser errors otherwise.

## Scene validation

- `tools/check_map.gd`, `tools/walk_test.gd`, `tools/lm_ghost.gd`,
  `tools/hieda_boundary_check.gd` are the static gates. They catch
  overlaps, unreachable routes, reservation overflow — they do **not**
  catch anything visual.
- After loosening any check, run a teeth-test: confirm it still fails on a
  known-bad input.
- Screenshots remain the only gate for "looks wrong". See
  `.claude/rules/art-review.md`.

## Scenes are committed artifacts

`godot/maps/*/gen/*.res` and `*.tscn` are generated but tracked. Regenerate
and commit them together with the generator change; never hand-edit them.
`shots2/` is a tracked directory — verification renders are committed.
