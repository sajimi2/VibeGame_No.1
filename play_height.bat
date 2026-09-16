@echo off
setlocal
set "ROOT=%~dp0"
set "GODOT=D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if /i "%~1"=="dev" goto :dev
start "" "%ROOT%builds\windows\OutpostRPG_HeightLab.exe"
exit /b 0
:dev
"%GODOT%" --path "%ROOT%." res://scenes/tactical_height.tscn
