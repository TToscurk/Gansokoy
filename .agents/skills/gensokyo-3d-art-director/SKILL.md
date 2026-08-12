---
name: gensokyo-3d-art-director
description: Direct and validate stylized Gensokyo/Touhou 3D environment assets produced through Blender Python and imported into Godot. Use when Codex or another coding agent works on Gansokoy, fantasy Japanese buildings, machiya, village props, environment prototypes, bpy asset generators, semantic materials, GLB export, Godot 3D import, visual polish, or ART_REVIEW. Preserve the repository's existing asset pipeline and contracts; improve silhouette, proportion, construction depth, materials, lighting, camera presentation, and game readability without silently replacing established generators or integration paths.
---

# Gensokyo 3D Art Director

Build production-ready stylized environment assets while treating the repository as the source of truth. Combine technical-art discipline with explicit visual review instead of equating successful export with acceptable art.

## Establish the contract

Before editing, inspect repository instructions and the asset task. Locate the relevant generator, compatibility helpers, material contract, exporter, existing peer assets, tests, and review-output conventions. Use `rg` and `rg --files` first.

Summarize the discovered contract internally as:

- editable asset and generator;
- protected files and forbidden integrations;
- required helpers and semantic material names;
- output formats and paths;
- target scale, performance tier, and review gate.

Never convert task-local restrictions—such as one branch name, commit SHA, or protected prototype—into permanent project policy. Obey them for the current task only.

## Preserve the existing pipeline

Reuse repository-owned generators, Blender compatibility helpers, material factories, naming rules, validators, and GLB export functions. Extend the smallest relevant surface.

Do not introduce Meshy, Hunyuan3D, marketplace assets, a parallel material system, a new exporter, or a second asset pipeline unless the user explicitly asks. Do not regenerate or integrate scenes outside the task scope. Preserve unrelated user changes and protected assets.

When `bpy` is unavailable, follow the repository or task's declared Blender setup. Keep environment setup isolated. Do not change dependency versions merely for convenience.

## Direct the asset

Translate the brief into a compact production specification before modeling:

1. Define the asset's gameplay role and viewing distances.
2. Identify three to five recognition landmarks.
3. Set bounding dimensions and a primary silhouette.
4. Separate primary masses, secondary construction, and tertiary accents.
5. Select a restrained semantic material palette.
6. Define the review views and acceptance criteria.

For a Japanese fantasy building, prioritize roof silhouette, eave depth, facade bay rhythm, entrance hierarchy, visible structural members, grounded foundation, and believable side/rear treatment. Avoid a decorated box: create actual depth where it controls silhouette, parallax, contact shadow, or gameplay readability.

Favor reusable parameterized helpers over long sequences of one-off primitives. Keep random variation seeded when reproducibility matters. Name major objects and collections semantically.

## Apply the technical contract

### Use the repository as source of truth

Inspect `AGENTS.md`, `CLAUDE.md`, task specifications, generators, helpers, tests, and neighboring assets before choosing an implementation.

Prefer repository-native paths such as an existing `make_*.py`, `blender_compat.py`, semantic material factory, GLB exporter, and validation scripts. Search for function definitions and call sites before adding equivalents.

### Use Blender Python safely

- Match the declared Blender or `bpy` version and compatibility layer.
- Keep generation deterministic when artifacts are reviewed or committed.
- Apply transforms deliberately; avoid accidental scale or rotation differences between Blender and Godot.
- Recalculate or validate normals after topology-changing operations.
- Use bevels and weighted or smooth normals only where supported by the repository's Blender versions.
- Avoid context-sensitive `bpy.ops` when a data API or existing helper is safer.
- Preserve stable object, collection, and material names used by downstream scripts.

### Preserve semantic materials

Treat semantic material names as an integration contract, not decoration. Reuse the existing names and constructors exactly. Do not append automatic numeric suffixes or replace semantic slots with ad hoc visually similar materials.

Use material contrast to separate architectural layers, but keep engine-facing identity stable. Verify material slot assignment on exported meshes, not only in the Blender scene.

### Validate GLB and Godot output

Verify as applicable:

- expected GLB path and nonzero file size;
- correct axes, units, scale, origin, and grounded placement;
- transforms and modifiers evaluated as intended;
- outward normals and acceptable shading;
- semantic material slots retained;
- no unintended cameras, lights, duplicate meshes, or helper geometry;
- bounded mesh and material counts for the target performance tier;
- Godot import succeeds without changing unrelated scenes.

Do not regenerate a village scene or modify placement code unless integration is explicitly in scope.

Before editing, turn every `do not modify`, `do not integrate`, branch restriction, and stop condition into a checklist. Recheck the diff against it before handoff.

Never broaden a single-asset task into a pipeline rewrite. If the existing pipeline cannot produce the requested result, explain the concrete limitation and propose the smallest extension.

## Apply Gensokyo art direction

Judge quality in this order:

1. Recognizable silhouette at distance.
2. Convincing overall proportion and mass balance.
3. Clear structural hierarchy and facade rhythm.
4. Depth, overlap, and contact shadows.
5. Material grouping and value separation.
6. Selective story details and controlled imperfection.

Large-form failure cannot be repaired with lanterns, signs, trim, or noisy textures.

Use researched references appropriate to the requested place and era; do not blend shrine, temple, castle, farmhouse, and machiya motifs indiscriminately.

For machiya-like assets, evaluate:

- roof pitch, ridge, overhang, fascia, and eave thickness;
- facade bay spacing and the ratio of solids to openings;
- entrance hierarchy and threshold depth;
- posts, beams, lintels, rails, lattice rhythm, and grounded base;
- upper and lower floor relationship;
- side and rear elevations visible from gameplay paths;
- rain protection, drainage cues, signs, screens, or shop identity when appropriate.

Aim for an inhabited boundary-world rather than a generic historical museum. Combine a coherent traditional base with restrained fantasy accents, asymmetry, seasonal cues, signs of repair, or resident-specific storytelling. Let the requested character, district, mood, and game role determine accents; do not scatter fandom symbols everywhere.

- Exaggerate roof or eave silhouette slightly when needed for distance readability.
- Keep repeated elements rhythmic but avoid sterile perfect repetition.
- Use a limited palette with deliberate warm/cool and light/dark grouping.
- Prefer broad material response over texture noise.
- Keep damage and aging directional and plausible: exposed edges, water paths, foot traffic, soot, and repairs.
- Check the asset in neutral light before relying on dramatic presentation lighting.
- Test entrances, collision boundaries, walkable gaps, and interactable features from expected player height and distance.

## Run staged checks

Validate in this order:

1. **Structure:** run syntax or import checks and repository tests that do not mutate unrelated assets.
2. **Generation:** execute the existing asset generator through the declared Blender or `bpy` environment.
3. **Artifact:** confirm expected files exist and inspect scale, transforms, normals, materials, object hierarchy, and GLB contents with available tools.
4. **Visual:** render or capture the required views and inspect the actual images. Do not approve from logs alone.
5. **Engine:** perform Godot import or scene checks only when authorized by the task.

If rendering is unavailable, report the visual gate as unverified rather than guessing.

## Refine by failure dimension

Freeze a working artifact before refinement. Diagnose one dominant failure dimension at a time:

- silhouette and proportion;
- architectural hierarchy and depth;
- repeated rhythm and variation;
- material separation and roughness response;
- lighting and contact shadows;
- camera framing and scale communication;
- optimization or export integrity.

Make the smallest coherent revision, regenerate deterministically, and compare the same views. Do not add detail to disguise weak large forms.

## Enforce ART_REVIEW

Use consistent camera and lighting between iterations. Produce the views requested by the task; when unspecified, prefer:

- front three-quarter hero view;
- opposite rear three-quarter view;
- side or elevation view exposing depth;
- player-height or expected gameplay view;
- neutral-light material and readability view when presentation lighting is dramatic.

Use viewport captures only when they clearly show the evaluated properties. Prefer proper renders for material, light, and shadow judgments.

Score each area as pass, revise, or unverified:

- **Silhouette:** recognizable and intentionally weighted.
- **Proportion:** dimensions and floor/roof relationships feel coherent.
- **Construction:** visible forms appear supported and layered rather than pasted on.
- **Depth:** openings, eaves, frames, and foundation create meaningful parallax and contact shadow.
- **Rhythm:** repeated bays and lattice elements are controlled without mechanical deadness.
- **Materials:** semantic groups remain distinct under neutral and target lighting.
- **Lighting:** form is readable; highlights and shadows support rather than conceal it.
- **Camera:** review views communicate scale and reveal weaknesses.
- **Game view:** entrances and major shapes read from target distance.
- **Technical:** no obvious clipping, floating parts, broken normals, or export loss.

Do not mark a criterion as passed from source code, object counts, or successful export alone. If no image was inspected, mark visual criteria unverified.

Treat `ART_REVIEW` as a real handoff point. At that gate, present the asset and review evidence, list remaining risks, and stop before integration when the task says to stop. Do not edit village generators, `.tscn` scenes, placement logic, or unrelated assets merely to demonstrate the model.

Report:

- artifact identifier and output paths;
- files changed and validation results;
- contact sheet or individual review images;
- concise rubric results;
- strongest improvement and remaining limitations;
- whether downstream integration was intentionally deferred.
