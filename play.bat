@echo off
rem Outpost RPG launcher.
rem Kept ASCII-only on purpose: an earlier non-UTF8 PowerShell write corrupted this file once.
rem
rem   play.bat        double-click -> runs the exported standalone build (no Godot needed)
rem   play.bat dev    runs the project through the Godot engine, which picks up script and
rem                   scene changes without re-exporting

setlocal
set "ROOT=%~dp0"
rem Bump this line to the newest exported build: launching a stale build is the easiest way to
rem "re-test" a bug that was already fixed.
set "EXPORTED=%ROOT%builds\windows\OutpostRPG_v02_Stage3.exe"
set "GODOT=D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

if /i "%~1"=="dev" goto :dev

if not exist "%EXPORTED%" (
  echo Exported build not found:
  echo   %EXPORTED%
  echo.
  echo Build it with:
  echo   "%GODOT%" --headless --path "%ROOT%." --export-release "Windows Desktop" "%EXPORTED%"
  echo Or run the editor version:  play.bat dev
  echo.
  pause
  exit /b 1
)

start "" "%EXPORTED%"
exit /b 0

:dev
if not exist "%GODOT%" (
  echo Godot engine not found:
  echo   %GODOT%
  echo Edit the GODOT= line in this file if the engine has moved.
  echo.
  pause
  exit /b 1
)
cd /d "%ROOT%"
"%GODOT%" --path .
exit /b 0
