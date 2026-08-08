# Rule: Token Efficiency

**READ LESS · CHANGE LESS · VALIDATE WHAT CHANGED · PRESERVE APPROVED WORK ·
STOP WHEN TASK COMPLETE**

## Reading

- Start from `git status` / `git diff` / `git log --oneline -N`. The diff
  usually answers the question without opening a file.
- Grep for the symbol, then read the ±30 lines around it. Read whole files
  only when you must edit their structure.
- The generators are large (`gen_town.gd` ≈ 3.4k lines, `make_town.py`,
  `make_machiya.py`). Never read one end-to-end to "get oriented".
- Never re-audit the repository. `docs/PROJECT_STATE.md` is the audit.
- Do not re-investigate a decision listed in PROJECT_STATE's
  do-not-reopen section.

## Searching

- Prefer one precise grep over three broad ones.
- When a fact is already in `PROJECT_STATE.md` or a subsystem doc, cite it
  instead of re-deriving it from source.

## Writing

- Change the smallest set of lines that accomplishes the task.
- No drive-by renames, reformatting, or refactors.
- Do not add files that duplicate information already documented elsewhere.

## Reporting

- Final report: **Changed / Validation / Art Review / Known Risks / Status**.
- No implementation diary, no history recap, no option surveys you did not
  pursue.
- Corrections only when they change the user's decisions.

## The one thing efficiency may not touch

Validation. Renders, gates, and screenshots are not optional overhead —
in this repo they are the only things that catch "it looks wrong". If a
task's budget is tight, cut scope, not verification.
