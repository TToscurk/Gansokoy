#!/usr/bin/env bash
# 建築快速通道：一支指令把 GLB 建築放進地圖（說明見 place_building.gd 檔頭）。
#   bash godot/tools/fastlane/place_building.sh --glb="D:/資產glb/町家/農舍.glb" --id=farmhouse_a --at=120,-40 --yaw=90 --height=7
# 步驟：複製 GLB → Godot 匯入（自動 LOD）→ place_building.gd（需要畫面，會開一個視窗截圖；不加 --headless）。
# 其餘參數原樣傳給 place_building.gd。只移除：bash place_building.sh --id=<id> --remove
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 99          # → godot/
G="${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
glb="" ; id=""
for a in "$@"; do
	case "$a" in
		--glb=*) glb="${a#--glb=}" ;;
		--id=*)  id="${a#--id=}" ;;
	esac
done
[ -n "$id" ] || { echo "[FASTLANE] FAIL 需要 --id="; exit 1; }
pass=()
for a in "$@"; do [[ "$a" == --glb=* ]] || pass+=("$a"); done
if [ -n "$glb" ]; then
	[ -f "$glb" ] || { echo "[FASTLANE] FAIL 找不到 $glb"; exit 1; }
	dst="assets/village_v2/fastlane/$id"
	mkdir -p "$dst"
	copied=0
	if ! cmp -s "$glb" "$dst/$id.glb"; then
		cp "$glb" "$dst/$id.glb"
		copied=1
		echo "[FASTLANE] 複製 $glb → godot/$dst/$id.glb"
	fi
	printf '%s\n' "$glb" > "$dst/source.txt"
	if [ $copied -eq 1 ] || [ ! -f "$dst/$id.glb.import" ]; then
		echo "[FASTLANE] Godot 匯入中…"
		"$G" --headless --path . --import > /dev/null 2>&1 || true
	fi
	[ -f "$dst/$id.glb.import" ] || { echo "[FASTLANE] FAIL 匯入失敗（沒有 $dst/$id.glb.import）"; exit 1; }
fi
"$G" --path . --resolution 1280x720 --script res://tools/fastlane/place_building.gd -- "${pass[@]}"
