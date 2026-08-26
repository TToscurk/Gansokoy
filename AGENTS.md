# Repository Agent Instructions

## Mandatory Godot Project Skill

This repository is a Godot project; the live game project is under `godot/`.

The project-local `godot-master` skill at `.agents/skills/godot-master/SKILL.md`
is a **knowledge reference** for Godot API, performance, physics, and 3D topics.
Load only the single reference file needed for the current question; do not load
the entire reference library, and do not follow its Workflow 11–14 (Builder /
Agent Vision / Analyst / Auditor) — those are parallel pipelines banned by
`AGENT_CONSTITUTION.md`. Visual validation goes through this project's own
capture pipeline and Human Art Review only.

`AGENT_CONSTITUTION.md` remains the project-specific production authority. If a
generic `godot-master` recommendation conflicts with it or with the user's
current instruction, follow the constitution and the user's instruction.

The canonical on-demand routing rules are in `AGENT_CONSTITUTION.md` under
"Godot Skill 路由規則". In particular, scene design, road planning, 3D layout,
blockout, sightline, landmark-guidance, and level-flow work also requires the
project-local `.agents/skills/level-design/SKILL.md`; do not load or install
overlapping skills for the same task.

## Mandatory Production Constitution

Before starting any task, read and follow `AGENT_CONSTITUTION.md`.

Do not bypass it unless the user's current instruction explicitly overrides a specific rule.
