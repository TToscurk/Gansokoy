# Yoriichi Runtime

Read this file only when working on Yoriichi.

## Active Character

- Active prefab: `角色/緣一動作/yoriichi_character_meshy_full.tscn`.
- Body and Haori share one 24-bone Meshy skeleton.
- Runtime controller: `角色/緣一動作/yoriichi_character.gd`.
- Animation details and axis/root-motion notes: `角色/緣一動作/animations/README.md`.

## Implemented Runtime

- Idle / walk / run / directional locomotion.
- Draw / sheathe while moving.
- Drawn attacks and quick-draw flow.
- Dodge / roll with CharacterBody3D-driven movement.
- JumpStart / Fall / Land and air attack handling.
- Sword sockets / hand orientation fixes.
- AnimationTree-based layered controller for locomotion, upper-body actions, and full-body actions.
- Data-driven Sun Breathing slots exist; only forms with actual animation assets should be treated as implemented animation content.

## Current Boundary

**2026-09-03: wired into the main game.** `godot/scenes/main.tscn` instances
`res://characters/yoriichi/player_yoriichi.tscn` as `$Player`; the old
`scenes/player.tscn` capsule is no longer referenced. The in-`godot/` copy is
the runtime authority from here on:

- `godot/characters/yoriichi/` — minimal asset set (body FBX = the Walking
  clip's skin, sword GLB + textures, 16 derived `.res` animations, controller,
  `sun_breathing.gd`). The other 21 animation FBX (49 MB each) were **not**
  copied — every clip the controller plays is already baked into `animations/*.res`.
- `yoriichi_character.gd` differences from `角色/緣一動作/`: InputMap actions
  instead of raw keycodes (`move_*`, `sprint`, `jump`, `draw_sword`,
  `attack_light`, `attack_heavy`), `input_yaw_node` for camera-relative WASD,
  `step_height` ledge step-up, and two relayed signals main.gd subscribes to.
- `player_camera_adapter.gd` — mouse-look / SpringArm / zoom / InteractionRay
  child; no gameplay logic.
- `floor_max_angle` is 52° on the Player root (default 45°): the east river
  revetment and bridge abutments are 46–48° by design (`gen_terrain_river.gd`
  nominal 48°), and the coping lip needs both the raised angle and step-up.

Validation: `tools/verify_yoriichi_player.gd` (wiring, AnimationTree, stands,
walks), `tools/walk_slice.gd` (15 real-controller routes incl. both bridge
directions), `tools/audit_slice_collision.gd` (23 probes). All green 2026-09-03.

`角色/緣一動作/` remains the standalone tuning project; port changes forward
by hand — the two copies are not linked.

## Obsolete Track

The old procedural Y02 body/silhouette rebuild is not the active character path. Do not use its old ART_REVIEW gates as current instructions. Its historical notes were removed from the repo on 2026-08-26 (last copy in `work_backups/`, excluded from GitHub).
