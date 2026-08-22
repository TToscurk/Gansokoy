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

The character runtime is validated inside the Yoriichi character project, but it has **not yet replaced the formal Player in `godot/`**. Do not claim main-game integration until that wiring is completed and tested.

## Obsolete Track

The old procedural Y02 body/silhouette rebuild is not the active character path. Do not use its old ART_REVIEW gates as current instructions. Historical notes are kept in `docs/archive/yoriichi-character-legacy-2026-08-12.md` and should be read only for archaeology.
