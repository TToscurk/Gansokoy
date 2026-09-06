# Graph Report - godot custom code  (2026-09-01)

## Corpus Check
- 75 files · ~0 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 526 nodes · 971 edges · 53 communities (34 shown, 19 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 17 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- load map
- gen lib.gd
- gen kourindou.gd
- Portal Transition Regression Test
- gen hieda1f.gd
- gen hieda2f.gd
- gen hieda3f.gd
- check map.gd
- bank masonry.gd
- gen textures.gd
- gen terrain river.gd
- Gen Village Trees
- Hieda Boundary Acceptance Test
- process
- gen river vegetation.gd
- Build
- Hieda Garden MultiMesh Layout
- player.gd
- Trail Scene Generator
- asset probe.py
- canal water.gd
- init
- init
- weather.gd
- gen ground underlay.gd
- npc.gd
- sky cumulus.gdshader
- aze grid.gd
- coping grass.gd
- Rebuild
- Take Fence
- init
- emit
- init
- init
- filter
- init
- init
- path point
- ready
- sky panorama lift.gdshader
- init
- init
- init
- init
- init
- init
- init
- Hieda Garden
- on interaction message
- on interaction prompt changed
- on portal entered
- on portal reserved

## God Nodes (most connected - your core abstractions)
1. `load_map` - 21 edges
2. `World Map Registry` - 20 edges
3. `_init` - 15 edges
4. `_pattern` - 14 edges
5. `Portal Transition Regression Test` - 14 edges
6. `_check` - 13 edges
7. `_init` - 13 edges
8. `_init` - 13 edges
9. `_add` - 12 edges
10. `add` - 12 edges

## Surprising Connections (you probably didn't know these)
- `load_map` --references--> `Charpreview`  [EXTRACTED]
  godot/scripts/main.gd → godot/data/charpreview.meta.json
- `load_map` --references--> `Eientei`  [EXTRACTED]
  godot/scripts/main.gd → godot/data/eientei.meta.json
- `load_map` --references--> `Hieda3F`  [EXTRACTED]
  godot/scripts/main.gd → godot/data/hieda3f.meta.json
- `load_map` --references--> `Hinomiyagura`  [EXTRACTED]
  godot/scripts/main.gd → godot/data/hinomiyagura.meta.json
- `load_map` --references--> `Shrine`  [EXTRACTED]
  godot/scripts/main.gd → godot/data/shrine.meta.json

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Bamboo Region Portal Network** — godot_data_bamboo_meta_bamboo, godot_data_eientei_meta_eientei, godot_data_namelesshill_meta_namelesshill [EXTRACTED 1.00]
- **Hieda Interior Floor Chain** — godot_data_hieda1f_meta_hieda1f, godot_data_hieda2f_meta_hieda2f, godot_data_hieda3f_meta_hieda3f [EXTRACTED 1.00]
- **Scene Quality and Cleanup Pipeline** — godot_tools_check_map_script, godot_tools_clear_bright_grass_script, godot_tools_clear_street_vegetation_script, godot_tools_coping_grass_script [INFERRED 0.75]
- **Measured Landmark Placement Validation** — godot_tools_survey_hinomiyagura_init, godot_tools_place_hinomiyagura_init, godot_tools_hieda_boundary_check_check_footprint [INFERRED 0.75]
- **Godot Procedural Generation Suite** — godot_tools_gen_b1_street_script, godot_tools_gen_basin_hills_script, godot_tools_gen_charpreview_script, godot_tools_gen_ground_underlay_script, godot_tools_gen_hieda_script, godot_tools_gen_hieda1f_script, godot_tools_gen_hieda2f_script, godot_tools_gen_hieda3f_script, godot_tools_gen_hinomiyagura_preview_script, godot_tools_gen_hole_patches_script, godot_tools_gen_kourindou_script, godot_tools_gen_lib_script, godot_tools_gen_river_vegetation_script, godot_tools_gen_terrain_river_script, godot_tools_gen_textures_script [INFERRED 0.85]
- **Runtime Navigation Regression Suite** — godot_tools_interaction_test_init, godot_tools_portal_test_check_runtime_smoke_route, godot_tools_walk_test_route [INFERRED 0.85]
- **Editable Paddy Authoring Pipeline** — godot_tools_paddy_water_build, godot_tools_ine_scatter_build, godot_tools_ine_scatter_measure_mud_top [INFERRED 0.95]

## Communities (53 total, 19 thin omitted)

### Community 0 - "load map"
Cohesion: 0.08
Nodes (44): Bamboo, Charpreview, Eientei, Hieda1F, Hieda2F, Hieda3F, Hinomiyagura, Kourindou (+36 more)

### Community 1 - "gen lib.gd"
Cohesion: 0.10
Nodes (38): _init, add, blob_mesh, boundary, box, canopy_mat, char_scene, cyl (+30 more)

### Community 2 - "gen kourindou.gd"
Cohesion: 0.24
Nodes (27): _add, _box, _build_boundary, _build_env, _build_forest, _build_grass, _build_junk, _build_lamps (+19 more)

### Community 3 - "Portal Transition Regression Test"
Cohesion: 0.15
Nodes (28): Fail, Finish, _init, Village Interaction Regression Test, Teardown, Arrival For, Build Runtime Collisions, Capsule Overlaps (+20 more)

### Community 4 - "gen hieda1f.gd"
Cohesion: 0.19
Nodes (25): _build_books, _build_ceiling, _build_env, _build_floor, _build_furniture, _build_garden_backdrop, _build_light, _build_stairs (+17 more)

### Community 5 - "gen hieda2f.gd"
Cohesion: 0.20
Nodes (25): _build_ceiling, _build_daily_life, _build_desk, _build_env, _build_floor, _build_garden_backdrop, _build_light, _build_piles (+17 more)

### Community 6 - "gen hieda3f.gd"
Cohesion: 0.17
Nodes (25): _build_core, _build_cracks, _build_env, _build_floor, _build_light, _build_shell, _build_shelves, _build_stairwell (+17 more)

### Community 7 - "check map.gd"
Cohesion: 0.20
Nodes (23): _build_height_field, _check, _check_building_over_water, _check_building_overlap, _check_fauna, _check_floating, _check_mm_alive, _check_props_grounded (+15 more)

### Community 8 - "bank masonry.gd"
Cohesion: 0.16
Nodes (19): _add_mm, _build_coping, _build_piers, _build_weeps, _ready, _rebuild, _build, _find_mesh_recursive (+11 more)

### Community 9 - "gen textures.gd"
Cohesion: 0.19
Nodes (20): _bake, _fbm_field, _init, _lattice, _normal_from_height, _p_arakabe, _p_flag, _p_foliage (+12 more)

### Community 10 - "gen terrain river.gd"
Cohesion: 0.21
Nodes (17): _build_market, _build_paving, _build_row, _build_torii, _init, _local_bbox, _n2, _place (+9 more)

### Community 11 - "Gen Village Trees"
Cohesion: 0.26
Nodes (15): Bake, Blocked, Build Bonsai, Build Species, Density, Emit, _init, Gen Village Trees (+7 more)

### Community 12 - "Hieda Boundary Acceptance Test"
Cohesion: 0.35
Nodes (15): Check Approach, Check Content, Check Footprint, Check Grove, Check River, Check Towers, Est, _init (+7 more)

### Community 13 - "process"
Cohesion: 0.14
Nodes (14): _active_environment, _apply_ambient, _apply_lamps, clock_text, _current_map, _find_world_environment, _lamps, _process (+6 more)

### Community 14 - "gen river vegetation.gd"
Cohesion: 0.35
Nodes (11): _bake_photoscan_set, _bake_reed, _build_curves, _ground_y, _in_bridge_approach, _init, _make_item, _make_row (+3 more)

### Community 15 - "Build"
Cohesion: 0.30
Nodes (12): Build, Find Mesh Recursive, First Mesh, Measure Mud Top, _ready, Rebuild All, Ine Scatter, Build (+4 more)

### Community 16 - "Hieda Garden MultiMesh Layout"
Cohesion: 0.18
Nodes (11): Hieda Bush A, Hieda Bush B, Hieda Bush C, Hieda Hedge A, Hieda Hedge B, Hieda Hedge C, Hieda Maple A, Hieda Maple B (+3 more)

### Community 17 - "player.gd"
Cohesion: 0.29
Nodes (8): _find_interactable, _interact, _physics_process, _ready, _unhandled_input, _update_interaction_target, get_interaction_prompt, interact

### Community 18 - "Trail Scene Generator"
Cohesion: 0.51
Nodes (10): Build Env, Build Forest, Build Fork Landmark, Build Grass, Height At, _init, Mask At, Path Info (+2 more)

### Community 19 - "asset probe.py"
Cohesion: 0.36
Nodes (8): bl, classify, find_port, main, measure, place_y, scan, walkable_span

### Community 20 - "canal water.gd"
Cohesion: 0.46
Nodes (7): _build_mesh, _quad, _reach, _ready, _rebuild, _vert, _vertex_colour

### Community 21 - "init"
Cohesion: 0.39
Nodes (8): _init, Local Bbox, Place Hinomiyagura, Ground Y, _init, Load Ground, Survey Hinomiyagura, Wbox

### Community 22 - "init"
Cohesion: 0.52
Nodes (6): _aabb_covers_xz, _collect, _count_above, _init, _percentile, _tri_y_at

### Community 23 - "weather.gd"
Cohesion: 0.47
Nodes (5): _make_rain, _process, _ready, set_weather, _unhandled_input

### Community 24 - "gen ground underlay.gd"
Cohesion: 0.67
Nodes (5): _add_mesh, _bin_key, _init, _sample, _tri_y

### Community 25 - "npc.gd"
Cohesion: 0.60
Nodes (4): _point, _process, _ready, _register

### Community 26 - "sky cumulus.gdshader"
Cohesion: 0.70
Nodes (4): fbm, hash2, sky, vnoise

### Community 27 - "aze grid.gd"
Cohesion: 0.70
Nodes (4): _build, _find_mesh_recursive, _first_mesh, _ready

### Community 28 - "coping grass.gd"
Cohesion: 0.70
Nodes (4): _build, _find_mesh_recursive, _first_mesh, _ready

### Community 29 - "Rebuild"
Cohesion: 0.70
Nodes (5): Build Profile, Extrude, _ready, Rebuild, Parametric Town Canal

### Community 30 - "Take Fence"
Cohesion: 0.70
Nodes (5): Build, Find Mesh Recursive, First Mesh, _ready, Take Fence

### Community 31 - "init"
Cohesion: 1.00
Nodes (3): _init, _river_dist, _wkey

### Community 32 - "emit"
Cohesion: 0.83
Nodes (3): emit, _is_foliage, _xform

### Community 37 - "init"
Cohesion: 1.00
Nodes (3): _init, Run, Map Performance Probe

## Knowledge Gaps
- **54 isolated node(s):** `Charpreview`, `Hieda Bush A`, `Hieda Bush B`, `Hieda Bush C`, `Hieda Hedge A` (+49 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 62 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **19 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_ready` connect `load map` to `process`?**
  _High betweenness centrality (0.007) - this node is a cross-community bridge._
- **What connects `Charpreview`, `Hieda Bush A`, `Hieda Bush B` to the rest of the system?**
  _54 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `load map` be split into smaller, more focused modules?**
  _Cohesion score 0.080338266384778 - nodes in this community are weakly interconnected._
- **Should `gen lib.gd` be split into smaller, more focused modules?**
  _Cohesion score 0.09743589743589744 - nodes in this community are weakly interconnected._
- **Should `process` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._