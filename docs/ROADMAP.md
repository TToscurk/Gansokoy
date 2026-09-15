# ROADMAP

Status only. For current facts read `docs/PROJECT_STATE.md`. Implementation detail belongs in subsystem docs.

Last updated: 2026-09-09.

## DONE

- three.js line frozen; Godot 4.7 is the live build.
- 170-house procedural village generator retired and deleted (2026-08-25); village is a frozen committed scene.
- Human Village core layout, roads, river, portals, landmarks, production housing, main-street/facade work, and vegetation production passes.
- Yoriichi character-project runtime: Meshy full character, shared 24-bone skeleton, locomotion, draw/sheathe, attacks, dodge/roll, jump/fall/land, sword sockets, and AnimationTree controller.
- Repository cleanup pass removing obsolete web/review/generated files and adding ignore rules for local/generated artifacts.
- Git published to GitHub (`origin` = TToscurk/Gansokoy); LFS in use, branch-hygiene rules now in force.
- Beast trail (獸道) v2 linear rebuild + teleport wiring; 香霖堂 forest clearing redo.
- Slice performance pass: decimation, manual collision, cel-shading and SSR/SSIL environment tuning.
- 博麗神社 P0 blockout: terrain, spatial skeleton, commissioned shrine assets, 拜殿 stone platform.
- Sekiro-style combat: posture system, attack chaining, sun-halo dragon VFX, sword SFX.
- 山犬（雙尾狼）enemy: three-move AI, dissolve death, 牙通牙 spin attack.
- Prologue playable: quest/dialogue/story-flag systems and MQ00-MQ07 data, opening fade-in, 毛玉 and wounded-yokai events.

## CURRENT

- Prologue art and combat polish; 牙通牙 VFX still fails self-review.
- 博麗神社 courtyard scale and remaining shrine art-quality work.
- Human Village lighting / cel-shading and remaining visible art-quality work.

## NEXT

- Integrate the finished Yoriichi runtime into the formal `godot/` Player when explicitly started.
- Wire the 山犬 encounter into the beast trail for MQ02.
- Resolve remaining landmark / close-range prop quality debt.

## LATER

- Additional roof families and architecture vocabulary.
- Hand-authored LOD work.
- More props / villagers / polish.
- Other Gensokyo locations beyond the current Human Village / shrine scope.
