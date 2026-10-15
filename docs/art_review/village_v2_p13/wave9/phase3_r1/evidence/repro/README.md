# Phase 3 R1 の再現メモ（scratch のスクリプトの写し）
- `p3_at_{A,B,C}.txt`：TPS 鏡位（`名前:x,z,注視x,注視z;...`）。`p3_free_*.txt`：自由カメラの鏡位。
- `p3_run.sh`：Blender（`build_w9r2_arch.py`）→ import → prefab → `build_w9r2.gd`。`p3_shots.sh`：`w7_shots.gd` で撮影（BEFORE は `--swap=ArchW9R2P13=<1fdb647 の arch_w9r2_p13.scn>`、AFTER は現行）。
- 環境 overlay：`godot --headless --path godot --script res://tools/p13/w9/build_w9p3.gd -- --meadow-cache=<w9_meadow.json> [--dump=...]` → `-- --attach`。gate：`verify_w9p3.gd`。歩行：`walk_w9p3_real.gd`（OFF 基準→`--baseline=`）。効能：`w9p3_perf.gd`。
- 絶対パスは作業時のもの。BEFORE の arch は `git show 1fdb647:godot/maps/village_v2/gen/arch_w9r2_p13.scn`。
