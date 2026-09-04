#!/bin/sh
# 安裝專案的 git hooks。
#
#     sh godot/tools/install_hooks.sh
#
# .git/hooks/ 不在版控裡，所以 hook 本體放在 godot/tools/hooks/ 隨 repo 走，
# 這支負責複製過去。每次 clone 之後跑一次。
set -e
cd "$(dirname "$0")/../.."   # → repo 根目錄
SRC="godot/tools/hooks"
DST="$(git rev-parse --git-dir)/hooks"

for h in "$SRC"/*; do
	[ -f "$h" ] || continue
	name="$(basename "$h")"
	cp "$h" "$DST/$name"
	chmod +x "$DST/$name" 2>/dev/null || true
	echo "→ 已安裝 $name"
done
echo "hooks 安裝完成：$DST"
