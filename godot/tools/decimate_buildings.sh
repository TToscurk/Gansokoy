#!/usr/bin/env bash
# 建物／構造物 GLB 減面：gltfpack -si，原檔備份到 <dir>/_orig/。
# 可重複執行——每次都從備份讀，不會越減越爛。
#
# ⚠ 不加 -sa 時 gltfpack 會在「品質門檻」停手：實測目標 15% 只減到 61%。
#   -sa（aggressive）才會真的逼近 -si 的目標值。
# ⚠ gltfpack 是原生程式，MSYS 路徑不會被轉換，必須餵 D:/... 正斜線路徑。
set -u
cd /d/神社/shrine/godot || exit 1
GP=/c/Users/B365/AppData/Local/hermes/node/gltfpack
ROOT=D:/神社/shrine/godot

run() {
  local rel="$1" si="$2"
  local dir; dir=$(dirname "$rel")
  local base; base=$(basename "$rel")
  local orig="$dir/_orig"
  mkdir -p "$orig"
  local bak="$orig/$base"
  [ -f "$bak" ] || cp "$rel" "$bak"
  "$GP" -i "$ROOT/$bak" -o "$ROOT/$rel" -si "$si" -sa -kn -km -ke -noq > /dev/null 2>&1
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "FAIL $rel rc=$rc"
    cp "$bak" "$rel"
    return
  fi
  echo "OK   $rel si=$si"
}

# ── B1_Street 建物（佔該群 91%）──
run assets/_lod/小町家1.glb   0.12
run assets/_lod/市集商家.glb   0.12
run assets/_lod/大町家.glb     0.12
run assets/_lod/町家.glb      0.20
run assets/_lod/長屋.glb      0.20
run assets/_lod/倉庫.glb      0.20
# ── MachiCanal 最大戶：竹垣 141 份實例 ──
run assets/landscape/竹垣.glb  0.20
# ── 其他圖共用的大件 ──
run assets/_lod/寺子屋.glb     0.20
run assets/_lod/鯢吞亭.glb     0.20
run assets/_lod/霧雨店.glb     0.20
run assets/_lod/鈴奈庵.glb     0.20
run assets/_lod/稗田底新版.glb  0.20
run assets/_lod/農舍.glb      0.20
run assets/_lod/龍神像.glb     0.25
run assets/_lod/火見櫓.glb     0.25
run assets/_lod/遠景山.glb     0.15
echo "DONE"
