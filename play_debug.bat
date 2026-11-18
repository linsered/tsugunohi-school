@echo off
setlocal
cd /d "%~dp0"
echo Launching with console output...
"engine\godot.exe" --path "%~dp0." --resolution 1280x720 --verbose
pause
