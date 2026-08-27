---
name: godot-master
description: "Godot 4.7 API/pattern lookup for this project (3D fan game, desktop-first). Thin router: load only the single reference file the task needs. Architecture-level guidance lives in references/expert-core.md."
---

# Godot Master — Router

Target: **Godot 4.7+** (stable). This file only routes; load **one** reference
file per question. Do not read the whole library.

## Module Directory

### Architecture & Foundation
[Foundations](references/project-foundations.md) | [Composition](references/composition.md) | [Signals](references/signal-architecture.md) | [Autoloads](references/autoload-architecture.md) | [States](references/state-machine-advanced.md) | [Resources](references/resource-data-patterns.md) | [Templates](references/project-templates.md)

### GDScript & Testing
[GDScript Mastery](references/gdscript-mastery.md) | [Testing Patterns](references/testing-patterns-expert-testing-patterns.md) | [Debugging/Profiling](references/debugging-profiling.md) | [Performance Optimization](references/performance-optimization.md)

### 3D Systems
[3D Lighting](references/3d-lighting.md) | [3D Materials](references/3d-materials.md) | [3D World Building](references/3d-world-building.md) | [Physics 3D](references/physics-3d.md) | [Navigation/Pathfinding](references/navigation-pathfinding.md) | [AI Navigation](references/ai-navigation.md) | [Procedural Generation](references/procedural-generation.md) | [Raycasting](references/raycasting-queries.md)

### Animation & VFX
[Animation Player](references/animation-player.md) | [Animation Tree](references/animation-tree-mastery.md) | [Particles](references/particles.md) | [Tweening](references/tweening.md) | [Shader Basics](references/shaders-basics.md) | [Camera Systems](references/camera-systems.md)

### Gameplay & Systems
[Combat](references/combat-system.md) | [Audio](references/audio-systems.md) | [Scene Transitions](references/scene-management.md) | [Save/Load](references/save-load-systems.md) | [Input Handling](references/input-handling.md)

### UI
[UI Containers](references/ui-containers.md) | [Rich Text](references/ui-rich-text.md) | [Theming](references/ui-theming.md)

### Platforms
[Export Builds](references/export-builds.md) | [Desktop](references/platform-desktop.md) | [Web](references/platform-web.md)

### Architecture-level guidance (load only for system-design questions)
[Expert Core](references/expert-core.md) — thinking frameworks, decision
matrix, core workflows with per-workflow NEVER lists, performance budgets,
Server APIs / RID pattern, expert code patterns, 4.x gotchas, diagnostic
patterns, Unity→Godot translation.

## Hard Rules (always apply — full rationale in expert-core.md)

1. Never absolute node paths (`get_tree().root.get_node`); use `%UniqueName` / `@export NodePath`.
2. Never `load()` in hot paths or loops; `preload` or `ResourceLoader.load_threaded_request()`.
3. `@export` Resources are shared: `.duplicate()` in `_ready()` or enable Local-to-Scene.
4. Movement/hit detection in `_physics_process`, never `_process`; no `await` in `_physics_process`.
5. `StringName` (`&"key"`) for hot-path dictionary keys and signal names, not `String`.
6. Never scale `CollisionShape` nodes; resize the shape resource.
7. Foliage/cutout: `ALPHA_SCISSOR`, never `TRANSPARENCY_ALPHA`/`HASH`.
8. Never query `RenderingServer`/`PhysicsServer` getters in `_process` (sync stall).
9. Godot 4 signal syntax: `signal_name.connect(callable)`; Godot 3 string form silently no-ops.
10. Components emit signals; never mutate external state or call `parent.do_thing()`.
11. Tweens die with their creating node; kill in `_exit_tree()` or use `get_tree().create_tween()`.
12. Visual work is verified only by in-engine screenshots + Human Art Review (`.claude/rules/art-review.md`).

> Removed 2026-08-26 (backup: `work_backups/godot-master-trimmed_20260826/`): genre blueprints, 2D, mobile/console/VR, multiplayer, RPG/economy modules, Builder/Agent personas. For engine version migration use the upstream godot-version-migration skill, not this hub.

## Reference
- [Godot 4.7 Official Documentation](https://docs.godotengine.org/en/4.7/)
