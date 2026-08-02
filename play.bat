@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
REM ============================================================
REM  幻想鄉 3D —— 一鍵更新並開始遊玩（Windows）
REM
REM  做三件事：
REM    1. 從 GitHub 拉最新的程式碼
REM    2. 啟動開發伺服器（dev-server.mjs，每個回應都送 no-store）
REM    3. 開瀏覽器
REM
REM  為什麼一定要用 dev-server 而不是雙擊 index.html：
REM    ES module + importmap 會被 file:// 協定擋掉，遊戲根本不會啟動。
REM ============================================================
cd /d "%~dp0"

REM 要跟哪一條分支：優先讀「更新.bat」寫下的 .branch，沒有就用 main。
REM 也可以自己改這一行當預設值。
set BRANCH=main
if exist ".branch" (
  for /f "usebackq delims=" %%b in (".branch") do if not "%%b"=="" set "BRANCH=%%b"
)

echo.
echo ============================================
echo   幻想鄉 3D
echo ============================================
echo.

REM ---- 檢查 node ----
where node >nul 2>nul
if errorlevel 1 (
  echo [錯誤] 找不到 Node.js。
  echo.
  echo 請先到 https://nodejs.org/ 下載安裝（選 LTS 版），
  echo 安裝完關掉這個視窗，重新執行一次 play.bat。
  echo.
  pause
  exit /b 1
)

REM ---- 更新程式碼 ----
where git >nul 2>nul
if errorlevel 1 (
  echo [略過更新] 找不到 git，直接用現有的檔案啟動。
  echo             想自動更新的話請安裝 https://git-scm.com/
  echo.
  goto :serve
)

if not exist ".git" (
  echo [略過更新] 這個資料夾不是 git 儲存庫，直接用現有的檔案啟動。
  echo.
  goto :serve
)

REM 有沒有改到「已追蹤的檔案」？有的話不要硬蓋掉玩家的修改。
REM --untracked-files=no 是關鍵：你隨手在資料夾裡放一個筆記或截圖
REM 不該讓自動更新從此停擺，而 --ff-only 本來就不會動到未追蹤的檔案。
for /f %%i in ('git status --porcelain --untracked-files^=no 2^>nul') do set DIRTY=1
if defined DIRTY (
  echo [注意] 你有還沒提交的本機修改，這次不自動更新。
  echo        要保留修改就先 git stash 或 git commit，再重跑一次。
  echo.
  goto :serve
)

echo [1/3] 從 GitHub 抓取最新版本（分支：%BRANCH%）...
git fetch origin %BRANCH% 2>nul
if errorlevel 1 (
  echo       抓取失敗（可能是沒有網路）。用現有的檔案啟動。
  echo.
  goto :serve
)

REM 本地還沒有這條分支的話（例如「更新.bat」剛換過），順手建出來
git checkout %BRANCH% >nul 2>nul
if errorlevel 1 git checkout -B %BRANCH% origin/%BRANCH% >nul 2>nul
git merge --ff-only origin/%BRANCH% >nul 2>nul
if errorlevel 1 (
  echo       無法快進合併，可能本機有分岔的提交。用現有的檔案啟動。
) else (
  echo       完成。
)
echo.
echo       目前版本：
git log -1 --pretty=format:"      %%h  %%s"
echo.
echo.

:serve
echo [2/3] 啟動伺服器（http://localhost:5603）...
echo [3/3] 開啟瀏覽器...
echo.
echo ---------------------------------------------------------
echo   畫面沒更新的話，在瀏覽器按 Ctrl + Shift + R 強制重整。
echo   要關掉遊戲：回到這個視窗按 Ctrl + C，或直接關掉視窗。
echo ---------------------------------------------------------
echo.

start "" http://localhost:5603
node tools\dev-server.mjs . 5603
