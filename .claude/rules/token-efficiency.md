# Rule: Token Efficiency

**READ LESS · CHANGE LESS · VALIDATE WHAT CHANGED · PRESERVE APPROVED WORK ·
STOP WHEN TASK COMPLETE**

## Reading

- Start from `git status` / `git diff` / `git log --oneline -N`. The diff
  usually answers the question without opening a file.
- Grep for the symbol, then read the ±30 lines around it. Read whole files
  only when you must edit their structure.
- The Human Village is a frozen committed scene (`maps/village/village.tscn`
  + `gen/` artifacts); its old generator was retired 2026-08-25. Never read
  a generator end-to-end just to get oriented.
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
