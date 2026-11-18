@echo off
setlocal
cd /d "%~dp0"
if not exist "engine\godot.exe" (
  echo [ERROR] engine\godot.exe not found.
  pause
  exit /b 1
)
start "" "engine\godot.exe" --path "%~dp0." --resolution 1280x720
exit /b 0
