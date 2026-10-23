# 檔案樹比對：V1.3 備份 ↔ 現行（assets/beast_path、maps/beast_path、tools/beast_path、data/beast_path.meta.json）

備份 306 檔、現行 321 檔（略過 .import／.uid）。V1.3 備份＝`C:/Users/B365/AppData/Local/hermes/backups/beast_path_v13_20261015/godot`（341 檔 sha256 清單 `manifest_v13.sha256`）。

**assets／maps 之下與 S02／S03／S04、共用的 `bp_ground.*`／`bp_rock.*` 有關、內容不同的檔案：0 個**（無）

`maps/beast_path/beast_path.tscn` 的位元組不同只是 Godot 每次重生成會重抽 `unique_id`（語意比對 0 行差異）；`s01_terrain.res` 不同是因為多存了地表通道（頂點／法線／索引的雜湊與 V1.3 相同，見 `isolation.s01_terrain_locked`）。

## 內容不同（11）
- M `maps/beast_path/beast_path.tscn`
- M `maps/beast_path/gen/forest_plan.json`
- M `maps/beast_path/gen/s01_terrain.res`
- M `maps/beast_path/s01_entrance.tscn`
- M `tools/beast_path/forest_planner.gd`
- M `tools/beast_path/generate_beast_path.gd`
- M `tools/beast_path/layout_beast_path.json`
- M `tools/beast_path/perf_beast_path.gd`
- M `tools/beast_path/prop_builder.gd`
- M `tools/beast_path/terrain_generator.gd`
- M `tools/beast_path/verify_beast_path.gd`

## 新增（15）
- A `assets/beast_path/materials/bp_ground_s01.gdshader`
- A `assets/beast_path/materials/bp_ground_s01.tres`
- A `maps/beast_path/gen/s01_forest_inputs.json`
- A `tools/beast_path/frozen/layout_digest_v13.json`
- A `tools/beast_path/frozen/protected_v13_manifest.json`
- A `tools/beast_path/make_shots_s01.gd`
- A `tools/beast_path/probe_s01_density.gd`
- A `tools/beast_path/probe_s01_ground.gd`
- A `tools/beast_path/probe_s01_vis.gd`
- A `tools/beast_path/s01_forest.gd`
- A `tools/beast_path/s01_ground.gd`
- A `tools/beast_path/s01_tps_shots.gd`
- A `tools/beast_path/seam_shots.gd`
- A `tools/beast_path/verify_s01_gates.gd`
- A `tools/beast_path/verify_s01_negatives.gd`

## 移除（0）
