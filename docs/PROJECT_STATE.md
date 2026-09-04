# PROJECT STATE

Last updated: 2026-09-04.

This file is intentionally short. It contains only facts that should affect the next task. Load subsystem details only when that subsystem is being edited.

## Current Build

- Live game: **Godot 4.7** under `godot/` (`project.godot` features = 4.7; older docs saying 4.4 are historical).
- `src/` is the frozen three.js line.
- Human Village scene: `godot/maps/village/village.tscn` plus committed artifacts in `godot/maps/village/gen/`.
- **Active work happens in `godot/maps/slice/slice.tscn`**, not `village.tscn`. The slice
  is where B1/B2/B3 rounds, the canal, the east river and the collision work live; it is
  hand-tuned by the user between rounds and is now ~27 MB of scene text.
- Git repository initialized. Branch `main` is ahead 18 of origin; active branch
  `village-rebuild-b1-b2` has diverged (ahead/behind vs its own remote) — reconcile
  before pushing. Not yet on GitHub.

## Slice status (2026-09-04)

- Content is at capacity: 13,001 nodes / 6,483 visible meshes / ~44 M triangles.
  70 machiya, 14 landmarks, 2 torii, 415 water pieces, 208 trees, 3,118 ground-cover,
  2,609 rocks, 14 street lamps. `tools/survey_slice_content.gd` regenerates this census.
- Performance on a GTX 1070: main street 43-44 fps, riverside 44, village overview 31.
  **24.3 M triangles are still shadow casters after culling** — the real bottleneck.
  Top sources: `B1_Street` 5.1 M, `MachiCanal/TakeFence` (141 bamboo fences) 1.6 M,
  `VillageTrees`×5 at 2.36 M each. Cutting these is a visual trade-off and needs a
  user ruling, not an agent decision.
- Collision is complete and verified: 23/23 probe audit, 17/17 real-controller walk,
  675-sample ground-gap probe at zero deviation. Bodies: 71 convex hulls (avg 83 verts),
  15 cylinders (14 lamps), 10 trimeshes.
- Collision scenes are **binary `.scn`** (`gen/ground_collision.scn`,
  `building_collision.scn`, `lamp_collision.scn`). Text `.tscn` has no import cache, so
  it is re-parsed from decimal on every launch; the switch took F5 from 30.1 s to 19.3 s.
- Generators bake from **disk**, so `slice.tscn` must be saved in the editor before any
  `gen_*_collision.gd` run — otherwise hand-tuned positions bake at their old coordinates
  (this happened: 鯢吞亭 was 90 m out).
- Unused assets remaining: `assets/riverbank/` 9 (the paddy-field set: 稻作株, 水田一格,
  畦道, 洗物石段, 水車小屋, 木樋支撐棚架, 水車(窄), 收頭件大/小) and `assets/bridges/` 3
  (the live bridge is `imported_models/Stonebound Wooden Bri_1`). Using the paddy set
  means opening a whole new field area, not dressing the existing one.
- `check_map.gd -- slice` reports 12 issues; `tools/triage_check_map.gd` shows 10 of the
  11 "water buried underground" hits are false — the canal is a *dug* channel, so its
  water sits below village grade by design. The 2 empty MultiMesh layers
  (`GrassFlower`/`GrassTall`, 0 instances) are real leftovers superseded by `草筆刷_*`.

## Human Village — new baseline (user ruling 2026-08-26)

- The 170-house era is **fully retired and deleted (2026-08-25)** — generator pipeline (`gen_town.gd`, `tools/town/`, `make_town.py`, `make_machiya.py`, `town_modules.json`) **and the machiya assets, market, village gates, and portals**. None of these exist in the repo. Do not look for them, restore them, or treat docs describing them as current.
- **The current `village.tscn` IS the new baseline** (user ruling): landmarks 鎮守之杜, 稗田邸(+後院), 鈴奈庵, 寺子屋, 霧雨店, 鯢吞亭, 龍神像; 14 路燈; vegetation; vista; terrain; boundary. ~221 nodes. Future village content builds on top of this.
- The village is a **frozen, committed scene**: edit `village.tscn` / its `gen/` artifacts directly, following normal art-review gates.
- Remaining live generators: `gen_hieda*.gd`, `gen_kourindou.gd`, `gen_trail_v2.gd`, `gen_textures.gd`, `gen_charpreview.gd` + Blender `make_hieda/shourou/trees/props/hedge/chars.py`.
- Known naming wart: scene nodes and `gen/` folder use 「裨田邸」 (typo) for 稗田邸. Renaming touches scene references — leave as-is unless a task explicitly fixes it.
- Visual changes still require prototype → render → Human Art Review → rollout.
- Next major art direction is lighting / cel-shading.

## Beast Trail (獸道) v2 重構完成 (2026-09-04)

- **定位與規格**：南端（人里入口）至北端（神社傳送點）全線蛇行漸窄（路寬 2.8m → 1.3m），劃分 10 個張弛段落（農田/柵欄 → 界碑森林 → 密林1 → 疏段地藏 → 密林2 → 小溪木橋 → 獸道大空地 → 密林3妖怪痕跡 → 夜雀屋台 → 深處妖怪領域）。
- **產生器**：`godot/tools/gen_trail_v2.gd` 產出 `maps/trail/trail.tscn`（節點約 30,700 個、樹幹碰撞 1,080+ 根）。
- **自然與美術校正**：
  1. 樹種分配：闊葉 42%、松 33%、杉 20%、老歪樹 3%、枯樹 2%。前半段老樹全面覆寫綠葉，僅深處極稀疏紅葉。
  2. 密林感：樹木重兵配置在路沿 3.2m ~ 55m 帶狀區（路沿樹達 3,840+ 棵），營造林蔭穹頂。
  3. 空地與視線保護：空地半徑擴至 17m，古樹偏心置放並採自然綠葉闊葉巨木（CommonTree_1）；路心、屋台周圍與大空地完全禁入高草/大灌木，路面結實清晰。
  4. 螢火蟲粒子：白晝 `emitting = false`，光色柔綠微縮，消除黃色發光方塊。
- **測試驗收**：`walk_test.gd -- trail` 通過（0 條路線不通，BFS 全線暢通）；`check_map.gd -- trail` 水面正常開挖；截圖集存於 `docs/art_review/trail_v2/`。

## Yoriichi

- The old procedural Y02 rebuild track is obsolete and must not be treated as the active character workflow.
- Active character prefab: `角色/緣一動作/yoriichi_character_meshy_full.tscn`.
- Body and Haori use the same 24-bone Meshy skeleton.
- Runtime locomotion, draw/sheathe, attacks, dodge/roll, jump/fall/land, sword sockets, and the current AnimationTree controller have been implemented and validated at the character-project level.
- Yoriichi has **not yet replaced the formal Player in the main `godot/` game project**.
- Read `docs/yoriichi-runtime.md` only when working on Yoriichi.

## Village Rebuild — active work (2026-08-26)

- 視覺基準：`docs/reference/人間之里概念圖/村落農村概念俯視.png`（使用者裁決 2026-08-30，
  **圖本身是權威**）。圖上實況：市集主街貫穿村心、北面林丘社寺為視覺終點、
  西半住宅、東半農田＋大宅、東北河中平台立龍神像、細渠與水車穿行村內。
  `docs/village-concept-reference.md` 已於 2026-08-30 依圖校正（舊版有多處錯誤轉錄，
  含虛構的中央龍神廣場、北緣墓地、南緣 U 形河，已作廢）。
  ⚠️ slice 現行沿南緣的 U 形河**在概念圖上沒有依據**，出自使用者 2026-08-26 的
  獨立裁決，屬刻意偏離。
- River rework in progress on `maps/slice/slice.tscn`: ring/narrow versions v1–v5 were **rejected by the user (too narrow, not U-shaped)**; current candidate is `river_open_u` v6b (`shots2/river_open_u_v6b_*_20260826`), awaiting Human Art Review.
- River art card (user, 2026-08-26): **deep moat-like channel, stone-textured revetment, vegetation + trees along the banks**. The procedurally generated bridge is **placeholder only — do not treat it as final**; the user will replace it with a Meshy-made bridge.
- v7 pass applied on slice (2026-08-26 afternoon): 22 bank trees (round/pine/sakura mix at the three bridge areas, node `RiverV3_Candidate/RiverBankTrees`), stone revetment materials assigned (`river_ishigaki_dry.tres` on Dry banks, `river_ishigaki_wet.tres` on Wet banks; shared `2F岸石.tres` untouched). Shots: `shots2/river_open_u_v7*_20260826`.
- Bank trees were removed again on user order (2026-08-26 evening): trees/vegetation will come from Meshy; do not plant the existing tree_* GLBs along the river.
- A GPT repair attempt (2026-08-26, `repair_river_outer_transition.gd`, mesh swaps on Vista/OuterTerrainTransition, hidden vista trees) was **rejected by the user and fully reverted**; it is archived in `work_backups/gpt_river_attempt_20260826/` and is NOT part of the current scene.
- Second defect found the same way: `VillageLandExtension`, `EastTail/WestTailLandConnection`, `OuterTerrainTransition` shipped with **no material at all** (rendered white). Patched: earth on the extensions/tails, grass on the transition.
- Water is CLEAN — probe audit confirms `RiverWater` covers only the channel; earlier oversized-water suspicion was wrong.
- Materials ready: `river_ishigaki_dry.tres` / `river_ishigaki_wet.tres` (stone revetment, triplanar) and `river_transition_grass.tres` (double-sided matte grass) in `assets/materials/`. Audit tool kept at `godot/tools/audit_river_slice.gd`. The large arch visible at the east edge belongs to the pre-existing root `Vista` mesh, not the river banks; an A/B hide test exposed world void, so `Vista` remains unchanged pending a dedicated landscape-vista replacement.
- **v9 landscape pass (2026-08-26 night)**: continuous ground achieved — `GroundUnderlay` node (generated by `tools/gen_ground_underlay.gd`, 5m grid sampled 0.22m under every ground mesh, dips below the river bed inside the channel) fills all sky-holes between Terrain / VillageLandExtension / OuterTerrainTransition / hills. Fog fixed: `fog_density` 0.0016→0.0006, `volumetric_fog_density` 0.012→0.004, `volumetric_fog_sky_affect` 0.18→0 (this was the blocky-sky cause — froxel grid compositing onto the sky, not the cumulus shader). Evidence: `shots2/slice_v9c_fine_20260826`. GPT's rejected repair attempt archived in `work_backups/gpt_river_attempt_20260826/`.
- Next: user will apply zone material transitions on the ground for lived-in feel; vegetation/bridges via Meshy.
- **v10 pass (user round, 2026-08-26 night)**: (1) all three placeholder bridge assemblies removed (bridge, piers, abutments, foundations, collisions; land roads kept) — bridges will come from Meshy. (2) Remaining sky holes plugged: `tools/gen_hole_patches.gd` detects open-edge loops on Vista/OuterTerrainTransition and drops double-sided curtains from the rim to ground (`VistaHolePatches` node) — the east arch and west gap are now hill-coloured walls. (3) Bulges inside the revetment fixed for good: the ground underlay now **cuts out the whole channel band** (any cell touched by bank/water/bed emits no geometry) — verified by A/B hide test that the bulges were underlay poke-through. A cylindrical "VistaBackstop" attempt was ugly and was removed same-day. Evidence: `shots2/slice_v10e_cutout_20260826` + `slice_v10e_wide_20260826` (zero sky holes in all 8 cameras).
- **Vista redo step 1 done (2026-08-26 night, awaiting ART_REVIEW)**: old Vista + OuterTerrainTransition + curtain patches retired (the river-through-mountain hole is gone with them). New `BasinHills` ring generated by `tools/gen_basin_hills.gd` (deterministic seed 20260826): annulus r430-1250, 48 staggered mounds in 3 rows, north valley gap for the river exit, south highest, aerial-perspective vertex colours, **no trees (user supplies via Meshy 7)**. River clearance verified numerically: hills forced to 0 within 45m of water (12.7m of would-be hill suppressed). Mountains (150-300m) come from the user via Meshy per docs/vista-basin-plan.md; fog-band rework is plan step 4, still pending.
- **East river R3 continuation (2026-08-27, awaiting ART_REVIEW)**: `tools/gen_terrain_river.gd` now builds the stone revetment as a cross-segmented skin sampled from the exact ground-triangle interpolation, replacing R2's single chord that intersected the curved bank. By user ruling, the river generator no longer reserves or flattens an island for the current dragon statue and no longer interrupts either revetment beside it; ground, water, and banks pass continuously through that location. The statue node is intentionally untouched and may intersect the river until the user replaces it. Evidence: `shots2/east_river_r2_before_20260827`, `shots2/dragon_pool_r2_before_20260827`, `shots2/east_river_r3_through_20260827`, and `shots2/dragon_pool_r3_through_20260827`.
- **Unified terrain + B-scale river candidate (2026-08-27, awaiting ART_REVIEW)**: the slice village floor and basin hills now use one continuous `slice_unified_ground.res`; the old embedded `Terrain` visual is hidden. `unified_terrain.gdshader` blends ochre village soil, grass hills, and stone revetment from vertex masks on that one mesh, so the bank is no longer a raised/overlapping skin. User-selected river dimensions are about 44m water, 68m valley top, and 6m drop; water and valley continue through both map boundaries. The dragon statue was not moved. Geometry audit: 0 non-finite vertices, 0 downward normals, sampled water width 39.84-44.98m; `check_map.gd -- slice` and `walk_test.gd -- slice` passed. Evidence: `shots2/terrain_river_B_before_20260827`, `shots2/terrain_river_B_after2_20260827`, `shots2/terrain_basin_B_before_20260827`, and `shots2/terrain_basin_B_after2_20260827`.
- **Reference revetment pass (2026-08-27, ART_APPROVED by user)**: the user confirmed the result matches the reference. The B-scale river uses a river-aligned 5.5m-run engineered wall (nominal face angle about 48 degrees), a packed ochre crest path, and dry/wet stone vertex masks. A continuous conservative ground slope remains sealed beneath the 4m-sampled revetment cap, avoiding both terrain holes and the jagged silhouette produced by forcing the steep face into the 6m world grid. The dragon statue, water scale, and 68m valley-top envelope are unchanged. Final audit: ground/water/revetment each have 0 non-finite vertices and 0 downward normals; sampled water rows are 37.98-50.66m under organic width variation; `check_map.gd -- slice` reports 0 issues and `walk_test.gd -- slice` reports 0 blocked routes. Evidence: `shots2/revetment_ref_before_20260827` and `shots2/revetment_ref_after3_20260827`.
- The thin bright waterline band remains optional lighting/material polish, not a blocker for the approved revetment geometry.
- **River crest vegetation belt (2026-08-28, awaiting ART_REVIEW)**: `tools/gen_river_vegetation.gd` builds `maps/slice/gen/river_vegetation.tscn`, a ProtonScatter rig instanced once from `slice.tscn`, to break the razor-straight ochre-path/grass seam down both banks. Ten scatter rows (five offsets per bank, from 2.6 m inside the seam to 7.2 m out into the grass) run along Curve3D paths whose points are computed from the same centreline, width and height maths as `gen_terrain_river.gd`, so nothing is raycast or floated; the offsets themselves wander on noise so the belt does not read as a drawn line. Assets are reused, not authored: `bamboo_a/b` meshes down-scaled to about 2 m stand in as reeds with `river_transition_grass.tres` as override material, plus `hieda_bush_a/b/c` on the grass side. The bridge approach at z=-144 is skipped for 32 m either side. No approved ground, water, or revetment artifact was regenerated. `check_map.gd -- slice` reports 0 issues and `walk_test.gd -- slice` reports 0 blocked routes with 85074/85075 standable cells. Evidence: `shots2/vegbelt_before_20260828` and `shots2/vegbelt_after_20260828`.
- **Photoscan upgrade of the belt (2026-08-28 later, awaiting ART_REVIEW)**: the user rejected the low-poly `hieda_bush` look and asked for UE5-grade quality. PolyHaven CC0 photoscans (1k) now live under `imported_models/polyhaven/` (shrub_01, nettle_plant, periwinkle_plant, fern_02, grass_medium_02, rock_moss_set_01; LICENSE.txt in the directory). `gen_river_vegetation.gd` bakes each scan to a single ArrayMesh in `maps/slice/gen/ph_*.res` with re-tuned foliage materials (alpha scissor 0.22, specular 0.05, double-sided) and scatters those: bush rows use the four green plants with shadows on, plus a sparse half-buried mossy-rock row (60 m spacing, 0.3 m sink). **Measured limit**: photoscan grass tufts and any leaf card below roughly pixel scale erode to white dust under gl_compatibility (no TAA / alpha-to-coverage) — grass tufts were removed again and plants run at 2.4-3.0x real scale to compensate; do not re-add thin photoscan foliage while the renderer is gl_compatibility. The Karoo-biome PolyHaven shrubs (shrub_02/03/04) look dead and were deleted. Evidence: `shots2/vegbelt_ph_final_20260828`.
- **Revetment de-flattening (2026-08-28 night, awaiting ART_REVIEW)**: per the user's 護岸強化 reference, the wall no longer reads as a texture on a ramp. (1) Geometry: the revetment cross-section now ends in a coping course — the face stops 0.45 m short of the crest and a stone lip rises 0.22 m proud of the path before dropping back (silhouette break at the top edge). (2) Shading: `unified_terrain.gdshader` gained triplanar whiteout normal mapping plus AO for the stone branch only (mesh has no UVs, so tangent-space NORMAL_MAP is unavailable); masonry set is PolyHaven CC0 `old_stone_wall` 2k saved as `assets/textures/ishigaki_old_stone_*_2k.jpg`. Stone tint 0.47 dry / 0.22-0.28 wet, texture scale 0.32 (~3.1 m tile). First attempt at 0.82 tint washed the wall limestone-white — recorded so it is not retried. Gates re-ran clean after the profile change. Evidence: `shots2/revetment2_after_20260828` vs `shots2/vegbelt_ph_final_20260828`.
- **Water flow + bridge steps (2026-08-28 late night, awaiting ART_REVIEW)**: user ruled the landmark scales stay untouched for now. (1) `gen_terrain_river.gd` bakes the local downstream direction into the water mesh's COLOR.gb; `water.gdshader` gained a gated flow-map path (`use_flow_vc`, enabled only in `east_river_water.tres`) with classic two-phase scrolling, so ripples travel along the meander instead of world +z; pond materials keep the legacy path. (2) The bright waterline band's root cause was the semi-transparent shallow zone glowing with the ochre dirt bed underneath — submerged ground cells now carry wet-stone vertex colour; shore foam is additionally torn into lapping segments by a flow-scrolled noise mask and dimmed. (3) New `east_river_steps.res` (+`EastRiverSteps` node): a 3 m stone landing stair, 19 steps from the west crest path through the wall face to below waterline at z=-115 — placed clear of the Meshy bridge deck, whose approach ramp reaches ~z=-128 (first placement at z=-130 collided with it; recorded). Gates clean. Evidence: `shots2/water_steps_before_20260828` vs `shots2/water_steps_after_20260828` (`steps_axis`/`steps_top` are new-object framing shots).
- **Vegetation debt + bridge-approach clearing (2026-08-28, awaiting ART_REVIEW)**: three fixes in `gen_river_vegetation.gd`. (1) PolyHaven scan SETS are now split — each MeshInstance3D child bakes to its own re-centred single-plant mesh (`gen/ph_<species>_<i>.res`, 19 singles) and the bush/rock rows mix the singles; the 6 m hedge-sliver footprints from the scale audit are gone, periwinkle held to 1.55x so its flowers stop reading fist-sized. (2) **Curve gaps never worked**: removing Curve3D control points just lets the curve interpolate across the hole and Create Along Edge fills it — the bridge clearing had been decorative since round one. Rows are now built as ARRAYS of curve segments, one ScatterShape per contiguous segment; a skip genuinely ends the segment. (3) The bridge 龍石像橋 sits rotated 17.3 deg, so an oriented approach corridor (axis (0.9548,-0.2977), half-length 150 m, half-width 12 m) clears both walkway directions on top of the ±32 m river-crossing band. Evidence: `shots2/bridge_approach_before/after_20260828` (west approach: reeds+giant ferns against the deck -> clean walkway line), regression `shots2/vegbelt_singles_20260828`. Gates clean.
- Do not integrate any river into `village.tscn` until the slice prototype is approved.

## Asset diet — 2026-08-28 (user-ordered)

- All Meshy GLBs under `maps/village/gen/` were re-exported via Blender: textures capped at 4096 (8K sources downscaled), all embedded images re-encoded WEBP q85, and three pathological meshes decimated (寺子屋 2.97M tris @0.35, 遠景山 2.97M @0.12, 稗田底新版 0.92M @0.5). Totals: 739MB -> 212MB across 21 files; visual A/B in `shots2/asset_diet_before/after_20260828` shows no perceptible change at review distances.
- Meshy sidecar textures (`*_base_color/_metallic_roughness/_normal` etc.) were dead weight — zero scene/material references (the GLBs embed their own copies) — and were deleted (~460MB).
- The three unreferenced manor generations (Serene Edo Estate / Mountain Garden Manor / Misty Mountain Sanctuary) were deleted on user order after preview renders.
- slice.tscn no longer embeds the four vegetation MultiMesh buffers (the "binary data" save warning): they live in `maps/slice/gen/veg_mm_*.res` (compressed). Scene text 6.0MB -> 3.9MB, node structure verified identical (90 nodes), gates clean.
- Generated river meshes save with `ResourceSaver.FLAG_COMPRESS`.
- **GitHub blocker note**: history still contains >100MB blobs (Misty 174MB, 遠景山 112MB) from before the diet; first push requires either `git lfs migrate import --include="*.glb" --everything` or a one-off history rewrite. Working tree itself is now free of >100MB files outside `.godot` cache.

## Asset Pipeline — user ruling 2026-08-26

- **LLM-written procedural 3D asset generation (bpy code producing props/buildings) is REJECTED for new visible assets** — quality verdict: too ugly. New visible 3D assets come from the **image-AI → Meshy 7** workflow (image concept → Meshy image-to-3D → Godot import), same lineage as the Yoriichi character and `godot/imported_models/`.
- Procedural generation remains acceptable only for non-asset scene work: terrain shaping, water surfaces, scattering/placement, and utility geometry.
- Existing baked assets in the current baseline stay as-is until individually replaced.

## Current Priorities

1. Keep the working copy clean and avoid reviving obsolete prototype/review workflows or the retired village generator.
2. Continue Human Village lighting / cel-shading and remaining visible art-quality work.
3. Integrate the finished Yoriichi runtime into the formal game Player only when that task is explicitly started.

## Open decisions (waiting on the user)

- **圍牆 scale.** `imported_models/Japanese Castle Wall` is placed at scale 20 =
  8.18 m tall / 5.10 m thick / 37.98 m per segment. Real 築地塀 is 2.2-3.0 m; the user
  picked 2.41 m (scale 5.9) but the scene still holds scale 20. Four segments sit at
  (210.5, 93.8), (263.1, 93.8), (209.1, -76.2), (261.7, -76.2) — two rows flanking the
  north and south torii. **These are deliberate placements, not duplicates** (an agent
  misread them as a 4× stack and nearly deleted them).
- **Shadow budget.** 24.3 M casting triangles is what holds the frame at 31-44 fps.
  Turning off casting for `TakeFence` / `VillageTrees` would buy the most, but that is a
  look decision. Street lamps were already switched off and bought nothing (0.7 % of the
  total, 44→43 fps, inside noise) — recorded so it is not retried as a fix.
- **Play boundary.** `tools/probe_play_bounds.gd`: 15 of 16 compass headings run 420 m+
  with no terrain stopping the player. A plan exists at
  `docs/plans/2026-09-04-圍牆佈局規劃.md` (invisible `StaticBody3D` bounds for movement,
  wall segments only as gate dressing) but has not been approved or built.

## Do Not Reopen Without Evidence

- Current `village.tscn` landmark placement (the new baseline).
- The 2026-08-25 retirement of the 170-house era (generator AND assets) and the 2026-08-26 new-baseline ruling.
- Godot front-face winding convention.

## Context Rule

Do not load `docs/archive/` by default. Historical documents are for archaeology only, not current instructions.
