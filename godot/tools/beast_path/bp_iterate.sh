#!/usr/bin/env bash
# 獸道單區迭代：一支指令跑完「重生成 → 驗證 → 該區審圖總表 → 其他區沒被動到」（使用者 2026-10-18 效率規則）。
#   bash godot/tools/beast_path/bp_iterate.sh --zone=S02 [--bake] [--no-gen] [--no-shots] [--only=cam1,cam2]
#   --bake      先重烘該區林床（bake_s01_dress.gd，非 headless；改了 s0x_dress／floor 設定才需要）
#   --no-gen    不重生成（只改了鏡位或只想重拍）
#   --no-shots  不拍圖（只要數字）
#   --only      只拍指定鏡位（預設＝站在該區內的全部 bp_zone_shots 鏡位）
# 產出：docs/art_review/beast_path_latest/<zone>_sheet.jpg（每次覆寫，一張總表）＋ verify JSON（scratch）。
# 隔離證據＝git：印出其他區的場景／gen 檔相對 HEAD 有沒有變（取代舊的備份清單／雜湊對照）。
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 99          # → godot/
G="${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}"
S="C:/Users/B365/AppData/Local/hermes/cache/scratch/bp_iter"
zone="" ; gen=1 ; shots=1 ; bake=0 ; only=""
for a in "$@"; do
	case "$a" in
		--zone=*)   zone="${a#--zone=}" ;;
		--no-gen)   gen=0 ;;
		--no-shots) shots=0 ;;
		--bake)     bake=1 ;;
		--only=*)   only="$a" ;;
	esac
done
case "$zone" in S01|S02|S03|S04) ;; *) echo "[BP] FAIL 需要 --zone=S01|S02|S03|S04"; exit 1 ;; esac
z=$(echo "$zone" | tr 'A-Z' 'a-z')
t0=$(date +%s)
mkdir -p "$S"
step() { echo "[BP] $1（$(( $(date +%s) - t0 )) s）"; }

if [ $bake -eq 1 ]; then
	if [ "$zone" = S01 ]; then zarg=(); else zarg=(-- "--zone=$zone"); fi
	"$G" --path . --script res://tools/beast_path/bake_s01_dress.gd "${zarg[@]}" > "$S/bake_$z.log" 2>&1 \
		|| { grep -E 'ERROR|FAIL' "$S/bake_$z.log" | head -5; echo "[BP] FAIL 林床烘焙"; exit 1; }
	step "林床烘焙完成（log $S/bake_$z.log）"
fi
if [ $gen -eq 1 ]; then
	"$G" --headless --path . --script res://tools/beast_path/generate_beast_path.gd -- "--only=$zone" > "$S/gen_$z.log" 2>&1 \
		|| { grep -E 'SCRIPT ERROR|Parse Error|FAIL' "$S/gen_$z.log" | head -5; echo "[BP] FAIL 生成"; exit 1; }
	step "生成 $zone 完成"
	# 生成每次重抽 .tscn 的 unique_id：內容只差 unique_id 的場景檔還原成 HEAD，避免假變動污染下一區的隔離檢查
	for f in $(git diff --name-only -- maps/beast_path/*.tscn); do
		f="${f#godot/}"
		if diff -q <(git show "HEAD:godot/$f" | tr -d '\r' | sed -E 's/ unique_id=[0-9]+//') \
				<(tr -d '\r' < "$f" | sed -E 's/ unique_id=[0-9]+//') > /dev/null; then
			git checkout -q -- "$f" && echo "[BP] $f 只差 unique_id → 還原成 HEAD"
		fi
	done
fi
"$G" --headless --path . --script res://tools/beast_path/verify_beast_path.gd -- "--out=$S/verify.json" > "$S/verify_$z.log" 2>&1
grep -E '^\[FAIL\]|═══' "$S/verify_$z.log"
step "驗證完成（全文 $S/verify_$z.log）"
if [ $shots -eq 1 ]; then
	rm -rf "$S/shots_$z"
	"$G" --path . --script res://tools/beast_path/bp_zone_shots.gd -- --map=beast_path "--out=$S/shots_$z" --hour=10 "--zone=$zone" $only > "$S/shots_$z.log" 2>&1
	python tools/beast_path/bp_sheet.py "$S/shots_$z" "../docs/art_review/beast_path_latest/${zone}_sheet.jpg" \
		|| { tail -5 "$S/shots_$z.log"; echo "[BP] FAIL 截圖"; }
	step "審圖總表 docs/art_review/beast_path_latest/${zone}_sheet.jpg"
fi
# 隔離：其他區的場景與 gen 檔相對 HEAD
others=()
for o in S01 S02 S03 S04; do
	[ "$o" = "$zone" ] && continue
	oz=$(echo "$o" | tr 'A-Z' 'a-z')
	others+=(maps/beast_path/${oz}_*.tscn maps/beast_path/gen/${oz}_*)
done
changed=$(git status --porcelain -- "${others[@]}" 2>/dev/null | wc -l)
if [ "$changed" -eq 0 ]; then
	echo "[BP] PASS 其他區（$(echo S01 S02 S03 S04 | sed "s/$zone//")）的場景／gen 檔相對 git HEAD 沒有變動"
else
	echo "[BP] REVIEW 其他區有 $changed 個檔相對 git HEAD 有變動："
	git status --porcelain -- "${others[@]}" | head -10
fi
step "全部完成"
