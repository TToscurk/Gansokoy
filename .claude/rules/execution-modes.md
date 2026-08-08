# Rule: Execution Modes

Every task runs in exactly one of two modes. The mode is set by the human and
recorded per subsystem in `docs/PROJECT_STATE.md`. If it is not stated, ask —
do not guess.

---

## DESIGN MODE

Used **only** when one of these is genuinely unresolved:

- art direction,
- architecture language,
- world structure,
- a major gameplay decision.

In DESIGN MODE: produce a proposal, stop, and wait for **Human Art Review**.
Diagnosis and measurement are the deliverable; production changes are not.

## PRODUCTION MODE

Used after a direction has been approved. **Execute the full approved
deliverable autonomously.** Do not stop for micro-approvals.

| | |
|---|---|
| Phase numbers | Do **not** invent new Phase/subphase numbers for internal implementation steps. The batch has one name. |
| Ordinary technical decisions | Make them. Do not stop. |
| Recon | **One targeted pass maximum**, unless new evidence reveals a real blocker. |
| Validation during iteration | Cheap and relevant only. Run the **full suite once**, at meaningful batch completion. |
| RNG drift in decorative grass / props | Acceptable. Preserve it only when it is visually or mechanically significant. |
| Documentation | Update **once**, when the batch deliverable is complete. Not after every internal step. |
| Progress reports | None during the batch, unless blocked. One report at the end. |
| Obvious visual/technical defects inside the approved scope | Fix them without asking. |

### Protected invariants (production mode does not license these)

- roads and village structure
- landmark placement
- portals
- collision / gameplay
- approved compositions and **intentional** building placement

### Stop and ask only before

- changing road or village structure,
- moving a major landmark,
- changing approved art direction,
- changing gameplay or worldbuilding,
- a destructive decision with no safe rollback.

### Time-boxing investigation

If diagnosing a **non-blocking** problem runs past a reasonable effort, stop
diagnosing. Pick the **safest reversible option**, keep building, and record
the unknown in Known Risks. Unbounded recon is a failure mode, not diligence.

---

## What does not change in either mode

Validation itself. Renders, gates and screenshots stay mandatory at the points
where they apply — PRODUCTION MODE changes *when* the full suite runs, never
*whether* it runs. See `.claude/rules/art-review.md`.
