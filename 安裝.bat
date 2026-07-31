@echo off
chcp 65001 >nul
REM ============================================================
REM  幻想鄉 3D —— 全新安裝（Windows）
REM
REM  給「還沒把專案抓下來」的電腦用。放到任何一個空資料夾裡執行，
REM  它會把整個專案 clone 到旁邊的 Gansokoy 資料夾，然後直接開始玩。
REM
REM  之後每次要玩，改點 Gansokoy\play.bat 就好（那個會自動更新）。
REM ============================================================
setlocal
cd /d "%~dp0"

set REPO=https://github.com/TToscurk/Gansokoy.git
set DIR=Gansokoy
set BRANCH=claude/project-status-analysis-rffxia

echo.
echo ============================================
echo   幻想鄉 3D —— 全新安裝
echo ============================================
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

if exist "%DIR%\.git" (
  echo 偵測到已經安裝過了。改用 %DIR%\play.bat 啟動即可。
  echo.
  cd /d "%DIR%"
  call play.bat
  exit /b 0
)

echo 正在下載專案（第一次會花一點時間）...
git clone --branch %BRANCH% %REPO% "%DIR%"
if errorlevel 1 (
  echo.
  echo [錯誤] 下載失敗。可能的原因：
  echo   - 沒有網路
  echo   - 這是私有儲存庫，需要先在 git 設定好 GitHub 帳號
  echo.
  pause
  exit /b 1
)

echo.
echo 完成！接下來每次要玩，點 %DIR%\play.bat 就好。
echo.
cd /d "%DIR%"
call play.bat
