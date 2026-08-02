#!/usr/bin/env bash
# ============================================================
#  幻想鄉 3D —— 一鍵更新並開始遊玩（macOS / Linux）
#
#  做三件事：
#    1. 從 GitHub 拉最新的程式碼
#    2. 啟動開發伺服器（dev-server.mjs，每個回應都送 no-store）
#    3. 開瀏覽器
#
#  為什麼一定要用 dev-server 而不是直接開 index.html：
#    ES module + importmap 會被 file:// 協定擋掉，遊戲根本不會啟動。
#
#  第一次使用：chmod +x play.sh && ./play.sh
# ============================================================
set -u
cd "$(dirname "$0")"

# 要跟哪一條分支：優先讀 .branch（Windows 的「更新.bat」會寫這個檔），
# 沒有就用 main。也可以自己改這一行當預設值。
BRANCH="main"
[ -s .branch ] && BRANCH="$(head -n1 .branch | tr -d '[:space:]')"
PORT=5603

echo
echo "============================================"
echo "  幻想鄉 3D"
echo "============================================"
echo

# ---- 檢查 node ----
if ! command -v node >/dev/null 2>&1; then
  echo "[錯誤] 找不到 Node.js。"
  echo
  echo "請先安裝：https://nodejs.org/ （選 LTS 版）"
  echo "  macOS 也可以用：brew install node"
  echo
  exit 1
fi

# ---- 更新程式碼 ----
update() {
  if ! command -v git >/dev/null 2>&1; then
    echo "[略過更新] 找不到 git，直接用現有的檔案啟動。"
    return
  fi
  if [ ! -d .git ]; then
    echo "[略過更新] 這個資料夾不是 git 儲存庫，直接用現有的檔案啟動。"
    return
  fi
  # 有沒有改到「已追蹤的檔案」？有的話不要硬蓋掉玩家的修改。
  # --untracked-files=no 是關鍵：你隨手在資料夾裡放一個筆記或截圖
  # 不該讓自動更新從此停擺，而 --ff-only 本來就不會動到未追蹤的檔案。
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "[注意] 你有還沒提交的本機修改，這次不自動更新。"
    echo "       要保留修改就先 git stash 或 git commit，再重跑一次。"
    return
  fi

  echo "[1/3] 從 GitHub 抓取最新版本（分支：$BRANCH）..."
  if ! git fetch origin "$BRANCH" >/dev/null 2>&1; then
    echo "      抓取失敗（可能是沒有網路）。用現有的檔案啟動。"
    return
  fi
  # 本地還沒有這條分支的話順手建出來
  git checkout "$BRANCH" >/dev/null 2>&1 || git checkout -B "$BRANCH" "origin/$BRANCH" >/dev/null 2>&1
  if git merge --ff-only "origin/$BRANCH" >/dev/null 2>&1; then
    echo "      完成。"
  else
    echo "      無法快進合併，可能本機有分岔的提交。用現有的檔案啟動。"
  fi
  echo
  echo "      目前版本："
  git log -1 --pretty=format:"      %h  %s"
  echo
}
update
echo

# ---- 啟動 ----
echo "[2/3] 啟動伺服器（http://localhost:$PORT）..."
echo "[3/3] 開啟瀏覽器..."
echo
echo "---------------------------------------------------------"
echo "  畫面沒更新的話，在瀏覽器按 Cmd/Ctrl + Shift + R 強制重整。"
echo "  要關掉遊戲：回到這個視窗按 Ctrl + C。"
echo "---------------------------------------------------------"
echo

URL="http://localhost:$PORT"
# 伺服器起來之後再開瀏覽器，不然會看到「無法連線」
( sleep 1
  if command -v open >/dev/null 2>&1; then open "$URL"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$URL"
  else echo "請自行開啟瀏覽器連到 $URL"
  fi ) &

exec node tools/dev-server.mjs . "$PORT"
