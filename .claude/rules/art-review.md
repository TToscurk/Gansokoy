# Rule: Visual Validation & Human Art Review

## The gate order — never skip a step

```
prototype or slice  →  render  →  Human Art Review  →  rollout
```

- **Prototype / slice**: build the change on one module or in
  `maps/slice/` (10 lots, ~25 s regeneration). Never on `maps/village/`.
- **Render**: in-engine screenshots are mandatory. Static checkers have
  never once caught a "looks wrong" defect in this project — the missing
  sando, the sando trench, the floating gutter lid, the tile moiré, the
  black gable were all found in screenshots and by nothing else.
- **Human Art Review**: stop and wait. Do not proceed to the next phase on
  your own judgement.
- **Rollout**: only after explicit human approval, and only as far as the
  approval covers.

Never mass-deploy unapproved visual work. Approval of a prototype is not
approval to replace the village's 169 houses.

## Measure the artifact, not the parameter

Verify the exported mesh / generated scene / rendered image. A parameter
being set correctly is not evidence that the result is correct. Face counts
and bounding boxes compared against a known-good value catch silent
regressions (a doubled unit conversion showed up only as 2834 → 2858 faces).

## Rendering

- In-engine: `xvfb-run -a godot --rendering-driver opengl3 --path godot -- \
  --map=<id> --shots=res://tools/shots/<cfg>.json --shotdir=<abs path>`
- Blender neutral-stage renders for module review: neutral grey world, one
  sun + one fill, no fog, no DOF, no "cinematic" grading.
- Before/after comparisons: `godot/assets/blender/compare_renders.py`
  (this machine has no PIL / ImageMagick / system numpy — Blender carries
  its own). A comparison is only valid if **the camera did not move**.
- Preserve the previous approved render set as the BEFORE folder
  (`shots2/slice_16/`, `shots2/slice_17/`, …) before overwriting.
- Cameras: verify they are not inside a building, wall, or plant. Compute
  framing from the geometry, then check the actual image.

## Recording decisions

Write a human's art decision into the docs **only after** they approve it.
Record trade-offs honestly (e.g. "葺き足 0.265 → 0.46 is readability over
authenticity") rather than hiding them. Every visual round ends with an
honest list of what is still wrong.
