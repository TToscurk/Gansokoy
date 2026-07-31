@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
REM ============================================================
REM  幻想鄉 3D —— 安裝到「這個資料夾」（Windows）
REM
REM  把這個檔案放進你想要安裝的資料夾（例如 D:\神社\shrine）再執行，
REM  專案檔案就會直接落在那個資料夾裡 —— **不會**再多包一層子資料夾。
REM
REM  三種情況都處理：
REM    A. 資料夾已經是這個專案 → 直接更新並開始玩
REM    B. 資料夾是空的（或只有這個 bat）→ 就地安裝
REM    C. 資料夾裡有別的東西 → 先列出來讓你確認，不會偷偷覆蓋
REM
REM  裝好之後，每次要玩改點 play.bat 就行（那個會自動更新）。
REM ============================================================
cd /d "%~dp0"

set REPO=https://github.com/TToscurk/Gansokoy.git
set BRANCH=claude/project-status-analysis-rffxia

echo.
echo ============================================
echo   幻想鄉 3D —— 安裝
echo ============================================
echo.
echo 安裝位置：%CD%
echo.

REM ---- 檢查 node ----
where node >nul 2>nul
if errorlevel 1 (
  echo [錯誤] 找不到 Node.js。
  echo.
  echo 請先到 https://nodejs.org/ 下載安裝（選 LTS 版），
  echo 安裝完關掉這個視窗，重新執行一次。
  echo.
  pause
  exit /b 1
)

REM ---- 檢查 git ----
where git >nul 2>nul
if errorlevel 1 (
  echo [錯誤] 找不到 git。
  echo.
  echo 請先到 https://git-scm.com/ 下載安裝（一路按下一步即可），
  echo 安裝完關掉這個視窗，重新執行一次。
  echo.
  pause
  exit /b 1
)

REM ---- A. 已經裝好了 ----
if exist ".git" (
  echo 這個資料夾已經是專案本體了，直接更新並開始玩。
  echo.
  if exist "play.bat" (
    call play.bat
    exit /b 0
  )
  echo [注意] 找不到 play.bat，先抓一次最新版...
  git fetch origin %BRANCH%
  git checkout %BRANCH%
  git merge --ff-only origin/%BRANCH%
  call play.bat
  exit /b 0
)

REM ---- C. 資料夾裡有別的東西？先確認 ----
REM 數一下除了這個 bat 以外還有什麼（含資料夾）
set OTHERS=0
for %%f in (*) do (
  if /i not "%%~nxf"=="%~nx0" set /a OTHERS+=1
)
for /d %%d in (*) do set /a OTHERS+=1

if !OTHERS! GTR 0 (
  echo [注意] 這個資料夾裡已經有其他檔案：
  echo.
  for %%f in (*) do if /i not "%%~nxf"=="%~nx0" echo        %%~nxf
  for /d %%d in (*) do echo        %%~nxd\
  echo.
  echo 安裝會把專案檔案放進同一個資料夾。同名的檔案會被專案版本蓋掉。
  echo 不想蓋到東西的話，現在關掉視窗，改用一個空資料夾。
  echo.
  set /p GO=確定要繼續嗎？（輸入 y 再按 Enter）：
  if /i not "!GO!"=="y" (
    echo 已取消。
    pause
    exit /b 0
  )
  echo.
)

REM ---- B. 就地安裝 ----
REM 用 init + fetch + checkout 而不是 git clone：clone 只能把檔案放進
REM 一個「新建的」資料夾，做不到「裝在我現在這個資料夾」。
echo 正在下載專案（第一次會花一點時間）...
echo.
git init -q
git remote remove origin >nul 2>nul
git remote add origin %REPO%
git fetch origin %BRANCH%
if errorlevel 1 (
  echo.
  echo [錯誤] 下載失敗。可能的原因：
  echo   - 沒有網路
  echo   - 這是私有儲存庫，需要先在 git 設定好 GitHub 帳號
  echo.
  pause
  exit /b 1
)

REM -f：允許覆蓋同名的未追蹤檔案（上面已經讓你確認過了）
git checkout -f -B %BRANCH% origin/%BRANCH%
if errorlevel 1 (
  echo.
  echo [錯誤] 檔案展開失敗。
  echo.
  pause
  exit /b 1
)

echo.
echo ============================================
echo   安裝完成！
echo   之後每次要玩，點這個資料夾裡的 play.bat 就好。
echo ============================================
echo.
git log -1 --pretty=format:"  目前版本：%%h  %%s"
echo.
echo.
call play.bat
