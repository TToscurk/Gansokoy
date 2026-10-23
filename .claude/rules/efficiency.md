# Efficiency rules (user ruling 2026-10-18 — overrides older phase/process docs)

Full text: repo root `.hermes.md` → 效率規則. Summary:

1. **New buildings go through the fast lane**, one command:
   `bash godot/tools/fastlane/place_building.sh --glb=<GLB> --id=<ascii_id> --at=x,z [--yaw=deg] [--height=m] [--find=R] [--replace=NodePath] [--dry]`
   It imports (auto LOD), builds mesh collision, grounds on terrain, runs three checks
   (ground relief / penetration / player access ring), shoots 4 player-eye views to
   `docs/fastlane/<id>/sheet.jpg`, and mounts `FastLane/<id>` in `village_v2.tscn`
   (each building is its own selectable scene). `--remove` undoes. Do not write Blender
   collision scripts, asset.json gate_spec, registry entries or new gates for new buildings.
2. **Verification budget**: local checks + at most 4 shots. `run_village_v2_regression.sh`
   defaults to FAST (4 items, ~1.5 min; the 19-point walk is --full only); `--full` only at milestones, before a batch commit, or on request.
   Add a gate/negative case only when the same bug happens a second time.
3. **Light evidence**: no per-round `evidence/` / `repro/` / `review/` folders or long reports.
   Report = measured numbers in chat + one contact sheet + the commit message.
4. **Seals retired**: no new `data/*_seal.json`, no reopen/reseal chains; a git commit is the freeze.
   Seal hash mismatches after direct edits are expected (`--seals` only to compare history).
5. **No village regeneration**: `village_v2.tscn` is the hand-edited source of truth.
   `gen_village_v2.gd` refuses to write unless `VILLAGE_V2_ALLOW_REGEN=1` (a regen drops every
   overlay and hand edit). Edit nodes or the owning overlay scene directly — via MCP, the
   editor or text insertion — instead of stacking another fix-up overlay.
6. Beast path (獸道) single-zone iteration: `bash godot/tools/beast_path/bp_iterate.sh --zone=S0x
   [--bake] [--no-gen] [--no-shots]` = generate → verify → one zone contact sheet → other zones
   unchanged vs git HEAD. Isolation is git; no backups/manifests/replay A/B. Old freeze gates are INFO
   (`--legacy-freeze` restores FAIL). Image review per round: ≤ 1 sheet + 4 single shots.

Still in force: only the user grants `ART_APPROVED`; MultiMesh bakes never run `--headless`;
check the editor is closed (or edit through it) before writing a scene file.
