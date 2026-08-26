# Rule: Autonomy Level (subordinate to AGENT_CONSTITUTION.md)

Task **type** is governed by `AGENT_CONSTITUTION.md` — the agent declares exactly
one of `ART_FAST` / `INTEGRATION` / `BUG_SWEEP` at startup. This file defines
only the orthogonal **autonomy axis**: how much the agent decides on its own
within that task. It is not a second mode system.

## DESIGN (proposal-first)

Applies **only** when one of these is genuinely unresolved:
art direction, architecture language, world structure, or a major gameplay
decision. Produce a proposal, stop, and wait for **Human Art Review**.
Diagnosis and measurement are the deliverable; production changes are not.

## PRODUCTION (default)

Applies whenever a direction has already been approved — this is the default;
do not ask which level applies unless the task is genuinely a DESIGN case.
**Execute the full approved deliverable autonomously.** Do not stop for
micro-approvals.

| | |
|---|---|
| Ordinary technical decisions | Make them. Do not stop. |
| Recon | **One targeted pass maximum**, unless new evidence reveals a real blocker. |
| Validation during iteration | Cheap and relevant only. Run the **full suite once**, at meaningful batch completion. |
| Documentation | Update **once**, when the batch deliverable is complete. |
| Progress reports | None during the batch, unless blocked. One report at the end. |
| Obvious defects inside the approved scope | Fix them without asking. |

Autonomy never overrides 紅線 6: the agent may reach at most `ART_REVIEW`;
only the user declares visual work approved.

### Protected invariants (autonomy does not license these)

- village structure and landmark placement (current `village.tscn` baseline)
- collision / gameplay
- approved compositions and intentional placement

### Stop and ask only before

- moving a major landmark or changing village structure,
- changing approved art direction,
- changing gameplay or worldbuilding,
- a destructive decision with no safe rollback.

### Time-boxing investigation

If diagnosing a **non-blocking** problem runs past a reasonable effort, stop
diagnosing. Pick the **safest reversible option**, keep building, and record
the unknown in Known Risks. Unbounded recon is a failure mode, not diligence.

## What never changes

Validation itself. Renders, gates and screenshots stay mandatory at the points
where they apply — autonomy changes *when* the full suite runs, never
*whether* it runs. See `.claude/rules/art-review.md`.
