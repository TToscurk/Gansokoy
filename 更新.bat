@echo off
chcp 65001 >nul
cd /d "%~dp0"
REM ============================================================
REM  Gansokoy branch updater (Windows)
REM
REM  IMPORTANT: keep this file PURE ASCII.
REM  cmd.exe tracks its position in a batch file by BYTE offset but
REM  recomputes it in CHARACTERS after chcp 65001, so any non-ASCII
REM  text makes execution drift into the middle of later lines.
REM  All user-facing (Chinese) text lives in tools\update.mjs.
REM ============================================================

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   [ERROR] Node.js not found. / Node.js
  echo.
  echo   https://nodejs.org/  LTS
  echo.
  pause
  exit /b 1
)

node "%~dp0tools\update.mjs"
if errorlevel 1 pause
exit /b 0
