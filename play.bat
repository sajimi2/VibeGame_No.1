@echo off
setlocal
set "ROOT=%~dp0"
set "GODOT=%GODOT_BIN%"
if not defined GODOT if exist "%ROOT%..\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" set "GODOT=%ROOT%..\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT for %%G in (godot.exe) do set "GODOT=%%~$PATH:G"
if not defined GODOT (
  echo Godot not found. Set GODOT_BIN to your Godot 4.7.2 executable.
  pause
  exit /b 1
)
if not exist "%GODOT%" (
  echo GODOT_BIN does not point to an existing executable.
  pause
  exit /b 1
)
start "Outpost RPG" "%GODOT%" --path "%ROOT%." --fullscreen %*
