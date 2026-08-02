@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
REM ============================================================
REM  幻想鄉 3D —— 分支更新器（Windows）
REM
REM  play.bat 只會更新單一分支（預設 main）。開發中的東西常常還在
REM  別的分支上沒併進 main，那時候 play.bat 怎麼按都拉不到新檔案。
REM  這個腳本就是為了那種情況：
REM
REM    1. 一次抓下 GitHub 上「所有」分支
REM    2. 依最後更新時間由新到舊列給你看
REM    3. 你選一條 → 本地切過去，play.bat 之後也會跟著這條走
REM       （選擇記在 .branch 這個檔案裡）
REM
REM    另外有一個 [A] 選項：把每一條分支各自解到 branches\<分支名>\
REM    底下一份，全部分支的檔案同時存在本地，互不干擾（git worktree）。
REM ============================================================
cd /d "%~dp0"

set "BRANCHFILE=.branch"
set "LIST=%TEMP%\gansokoy_branches.txt"

echo.
echo ============================================
echo   幻想鄉 3D —— 分支更新器
echo ============================================
echo.

REM ---- 前置檢查 ----
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

if not exist ".git" (
  echo [錯誤] 這個資料夾不是 git 儲存庫。
  echo.
  echo 請先執行「安裝.bat」把專案抓下來，再用這個腳本切分支。
  echo.
  pause
  exit /b 1
)

REM ---- 有沒有沒提交的本機修改？有的話先講清楚 ----
REM --untracked-files=no：你隨手在資料夾裡放筆記或截圖不該擋住更新
set "DIRTY="
for /f %%i in ('git status --porcelain --untracked-files^=no 2^>nul') do set DIRTY=1
if defined DIRTY (
  echo [注意] 你有還沒提交的本機修改：
  echo.
  git status --short --untracked-files=no
  echo.
  echo 切換分支會覆蓋掉這些修改。要保留就先關掉這個視窗，
  echo 執行 git stash 或 git commit，再重跑一次。
  echo.
  set /p GO=確定要繼續並丟掉這些修改嗎？（輸入 y 再按 Enter）：
  if /i not "!GO!"=="y" (
    echo 已取消。
    pause
    exit /b 0
  )
  echo.
)

REM ---- 抓所有分支 ----
echo [1/3] 從 GitHub 抓取所有分支...
git fetch origin --prune
if errorlevel 1 (
  echo.
  echo [錯誤] 抓取失敗。可能的原因：
  echo   - 沒有網路
  echo   - 這是私有儲存庫，需要先在 git 設定好 GitHub 帳號
  echo.
  pause
  exit /b 1
)
echo       完成。
echo.

REM ---- 列出來（依最後更新時間，新的在上面）----
REM 先倒進暫存檔再讀。直接在 for /f 裡跑 git，格式字串的括號會被
REM 批次檔的括號解析吃掉，這是繞開那個坑最穩的寫法。
git for-each-ref --sort=-committerdate --format="%%(refname:short) %%(committerdate:short) %%(subject)" refs/remotes/origin > "%LIST%" 2>nul

echo [2/3] GitHub 上的分支（由新到舊）：
echo.

set N=0
for /f "usebackq tokens=1,2,* delims= " %%a in ("%LIST%") do (
  set "REF=%%a"
  if /i not "!REF!"=="origin/HEAD" (
    set "B=!REF:origin/=!"
    set /a N+=1
    set "BR[!N!]=!B!"
    echo   [!N!]  !B!
    echo         %%b   %%c
    echo.
  )
)

if %N%==0 (
  echo [錯誤] 一條分支都沒抓到，這不正常。
  echo.
  pause
  exit /b 1
)

echo   [A]  全部分支各解一份到 branches\ 資料夾底下
echo.

REM ---- 選 ----
set "SEL="
set /p SEL=請輸入編號（直接按 Enter = 1，最新的那條）：
if "!SEL!"=="" set SEL=1

if /i "!SEL!"=="A" goto :allbranches

set "TARGET=!BR[%SEL%]!"
if "!TARGET!"=="" (
  echo.
  echo [錯誤] 沒有編號 !SEL! 這個選項。
  echo.
  pause
  exit /b 1
)

echo.
echo [3/3] 切換到 !TARGET! ...
git checkout -B "!TARGET!" "origin/!TARGET!"
if errorlevel 1 (
  echo.
  echo [錯誤] 切換失敗。
  echo.
  pause
  exit /b 1
)
git branch --set-upstream-to="origin/!TARGET!" >nul 2>nul

REM 記住選擇，play.bat 會讀這個檔
> "%BRANCHFILE%" echo !TARGET!

echo.
echo ============================================
echo   已更新到 !TARGET!
echo ============================================
echo.
git log -1 --pretty=format:"  目前版本：%%h  %%ad  %%s" --date=format:"%%m-%%d %%H:%%M"
echo.
echo.
echo   之後直接點 play.bat 就會跟著這條分支更新。
echo   要換回 main 就再跑一次這個腳本。
echo.

set "PLAY="
set /p PLAY=現在開始遊玩嗎？（直接按 Enter = 是，輸入 n = 否）：
if /i "!PLAY!"=="n" (
  pause
  exit /b 0
)
call play.bat
exit /b 0


REM ============================================================
REM  [A] 全部分支各解一份
REM ============================================================
:allbranches
echo.
echo [3/3] 把每一條分支各解一份到 branches\ 底下...
echo.
echo   用的是 git worktree：同一份 .git 歷史，多個工作目錄。
echo   不會重複下載，也不會互相干擾。
echo.

if not exist "branches" mkdir "branches"

set DONE=0
for /l %%i in (1,1,%N%) do (
  set "B=!BR[%%i]!"
  REM 資料夾名不能有斜線，claude/xxx 會變成 claude-xxx
  set "DIR=!B:/=-!"
  if exist "branches\!DIR!" (
    echo   [跳過] branches\!DIR!  已經存在，改成就地更新
    pushd "branches\!DIR!"
    git merge --ff-only "origin/!B!" >nul 2>nul
    popd
  ) else (
    echo   [建立] branches\!DIR!
    git worktree add "branches\!DIR!" "origin/!B!" --detach >nul 2>nul
    if errorlevel 1 (
      echo          失敗，跳過這條
    ) else (
      set /a DONE+=1
    )
  )
)

echo.
echo ============================================
echo   完成，共 !DONE! 條新解出來
echo ============================================
echo.
echo   每個資料夾都是一份完整可執行的遊戲。
echo   要玩哪一條就進去點裡面的 play.bat。
echo.
echo   注意：branches\ 底下那幾份不會自動更新，
echo   想更新就再跑一次這個腳本按 A。
echo.
echo   要整批砍掉：關掉遊戲後刪除 branches 資料夾，
echo   再回到這裡執行 git worktree prune 清乾淨。
echo.
pause
exit /b 0
