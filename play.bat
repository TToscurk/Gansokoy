@echo off
chcp 65001 >nul
cd /d "%~dp0"
REM ============================================================
REM  Gansokoy - update and play (Windows)
REM
REM  IMPORTANT: keep this file PURE ASCII.
REM  cmd.exe tracks its position in a batch file by BYTE offset but
REM  recomputes it in CHARACTERS after chcp 65001, so any non-ASCII
REM  text makes execution drift into the middle of later lines
REM  (that is what broke the first version of this script).
REM  All user-facing (Chinese) text lives in tools\play.mjs.
REM ============================================================

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   [ERROR] Node.js not found.
  echo.
  echo   Install the LTS build from https://nodejs.org/
  echo   then close this window and run play.bat again.
  echo.
  pause
  exit /b 1
)

node "%~dp0tools\play.mjs" 5603
if errorlevel 1 pause
exit /b 0
