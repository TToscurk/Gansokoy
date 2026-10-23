# Rule: Character animation work → animation-development-pipeline

Source of truth (single copy, Hermes skill):
`C:\Users\B365\AppData\Local\hermes\skills\godot\animation-development-pipeline\SKILL.md`
(read it and the matching `references/*.md` before acting; the same rule lives in repo-root `.hermes.md` for Hermes).

Use it when the request creates, modifies, retargets, repairs or compares **character motion itself**
(sword forms, blade path, attack timing, flips/jumps/landings, skeleton, IK, foot slide, clipping,
an NPC's pose/clip). Decide by meaning, not by the word 動作: changing only VFX colour, dialogue,
UI or NPC scheduling logic does not use it.

- Before editing: find the source assets/original version and their freeze state (`rNN/README.md`).
- After editing: verify by risk — FAST / STANDARD / DEEP; a complete change with visible behaviour
  change needs at least STANDARD. External video → existing `video-motion-analysis`; SAM 2 only when
  precise blade tracking is really needed.
- Subjective visual quality is ART_REVIEW; never auto-PASS (only the user grants ART_APPROVED).
- Tool inventory: `python <skill>/scripts/pipeline_launcher.py doctor --path A|B|C|D`.
