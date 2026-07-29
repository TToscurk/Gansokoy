@echo off
REM 博麗神社 3D — start the dev server and open the browser.
REM Uses dev-server.mjs rather than python's http.server: the latter lets the
REM browser cache ES modules, so edits under src\ silently have no effect.
cd /d "%~dp0"
start "" http://localhost:5603
node tools\dev-server.mjs . 5603
