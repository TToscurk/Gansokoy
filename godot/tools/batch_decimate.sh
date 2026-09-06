#!/usr/bin/env bash
# Batch-decimate the buildings that dominate maps/slice GPU cost.
#
# WHY 0.22: measured on 2026-09-03. gltfpack's UV-seam-preserving simplifier
# floors at ~22% on these Meshy models regardless of a lower -si value, and
# every attempt to go below it (aggressive mode -sa: 137k / 91k / 45k tris)
# visibly smeared the wall textures and shredded the roof ridge in side-by-side
# renders. 0.22 was the only ratio that survived Human Art Review framing with
# the silhouette and tile pattern intact.
#
# SAFETY (project constitution): sources are READ-ONLY. Output is written to a
# parallel _lod directory tree; no commissioned asset is overwritten, and no
# scene is rewired here. Wiring is a separate step, after ART_APPROVED.
#
# meshopt keeps UV seams and material boundaries welded, which the earlier
# pure-position decimator (tools/decimate_buildings.py) did not -- that one
# destroyed the roof at every ratio and is kept only as a reference.
set -euo pipefail

ROOT="D:/神社/shrine/godot"
RATIO="${RATIO:-0.22}"

FILES=(
  "assets/machiya/小町家1.glb"
  "assets/machiya/市集商家.glb"
  "assets/machiya/町家.glb"
  "assets/machiya/長屋.glb"
  "assets/machiya/倉庫.glb"
  "assets/machiya/大町家.glb"
  "assets/machiya/農舍.glb"
  "maps/village/gen/寺子屋/寺子屋.glb"
  "maps/village/gen/稗田邸/稗田底新版.glb"
  "maps/village/gen/山/遠景3/遠景山.glb"
  "maps/village/gen/龍神像/龍神像.glb"
  "maps/village/gen/鯢吞亭/鯢吞亭.glb"
  "maps/village/gen/霧雨店/霧雨店.glb"
  "maps/village/gen/鈴奈庵/鈴奈庵.glb"
  "assets/landmark/火見櫓.glb"
)

OUT_ROOT="$ROOT/assets/_lod"
mkdir -p "$OUT_ROOT"

printf '%-34s %10s %10s %6s\n' "模型" "原始面數" "減面後" "比例"
for rel in "${FILES[@]}"; do
  src="$ROOT/$rel"
  if [ ! -f "$src" ]; then
    printf '%-34s  來源不存在，跳過\n' "$(basename "$rel")"
    continue
  fi
  # Flatten into one directory, keyed by filename: every source basename in the
  # list is already unique, and a flat tree keeps the Godot import paths short.
  out="$OUT_ROOT/$(basename "$rel")"
  # -kn -km: preserve node hierarchy, names and distinct meshes (e.g. lanterns/signs on buildings)
  gltfpack -i "$src" -o "$out" -si "$RATIO" -noq -kn -km >/dev/null 2>&1
  python - "$src" "$out" "$(basename "$rel" .glb)" <<'PY'
import sys
from pygltflib import GLTF2
def tris(p):
    g = GLTF2().load(p)
    return sum(g.accessors[pr.indices].count // 3
               for m in g.meshes for pr in m.primitives if pr.indices is not None)
a, b = tris(sys.argv[1]), tris(sys.argv[2])
print('%-34s %10s %10s %5.0f%%' % (sys.argv[3], f'{a:,}', f'{b:,}', 100.0*b/max(a,1)))
PY
done
