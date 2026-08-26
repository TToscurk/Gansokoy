---
name: safe-production-commit
description: Safely finalize, validate, commit, and optionally push exactly one production subsystem in this repository. Use when a task ends with commit, push, ship, finalize, or "commit only this subsystem", especially when generators, rendered evidence, imports, or other unrelated working-tree files may be present.
---

# Safe Production Commit

Read `CLAUDE.md` and repository rules relevant to the subsystem. A request to commit one subsystem does not authorize including other worktree changes.

## Workflow

1. Inspect `git status --short` before cleanup or staging. Treat pre-existing and unrelated changes as user-owned.
2. Inspect `git diff --stat`, the actual relevant diff, and the untracked-file list. Confirm every intended generated artifact follows repository policy.
3. Remove or restore only known incidental output created by the current work. Never silently stage debug captures, caches, unrelated imports, regenerated assets, or another subsystem.
4. Run subsystem-relevant validation. For Godot map work, select from `godot/tools/check_map.gd`, `walk_test.gd`, `lm_ghost.gd`, `portal_test.gd`, and `hieda_boundary_check.gd`; include Blender export and Godot import/load checks when applicable.
5. Run `git diff --check` and resolve failures.
6. Stage explicit paths for the current subsystem. Review `git diff --cached --stat` and `git diff --cached` before committing.
7. Commit with a focused message. Do not begin the next subsystem.
8. Verify `git status --short` afterward and report any intentionally uncommitted files.
9. Push only when the user requested it and all required validation succeeded. Verify the pushed branch and commit hash.

Commit large generated files only when repository policy requires them. In this repository, `.claude/rules/godot.md` states that generated `godot/maps/*/gen/*.res` and map `.tscn` files are tracked artifacts; screenshots under `shots2/` are also tracked when they are required review evidence.
