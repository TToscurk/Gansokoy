# ROADMAP

Status only. For current facts read `docs/PROJECT_STATE.md`. Implementation detail belongs in subsystem docs.

## DONE

- three.js line frozen; Godot 4.4 is the live build.
- Human Village core layout, roads, river, portals, landmarks, production housing, main-street/facade work, and vegetation production passes.
- Yoriichi character-project runtime: Meshy full character, shared 24-bone skeleton, locomotion, draw/sheathe, attacks, dodge/roll, jump/fall/land, sword sockets, and AnimationTree controller.
- Repository cleanup pass removing obsolete web/review/generated files and adding ignore rules for local/generated artifacts.

## CURRENT

- Keep the cleaned `main` as the canonical base.
- Human Village lighting / cel-shading and remaining visible art-quality work.
- Review remaining old feature branches before deleting or selectively porting anything from them.

## NEXT

- Integrate the finished Yoriichi runtime into the formal `godot/` Player when explicitly started.
- Resolve remaining landmark / close-range prop quality debt.
- Continue lighting / cel-shading without reopening locked village structure.

## LATER

- Additional roof families and architecture vocabulary.
- Hand-authored LOD work.
- More props / villagers / polish.
- Other Gensokyo locations beyond the current Human Village / shrine scope.
