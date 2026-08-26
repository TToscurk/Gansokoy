@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture-godot.ps1" %*
exit /b %ERRORLEVEL%
