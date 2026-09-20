@echo off
setlocal
set "ROOT=%~dp0"
set "GODOT=%GODOT_BIN%"
if not defined GODOT set "GODOT=D:\vibe coding\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
"%GODOT%" --path "%ROOT%." res://scenes/painted_courtyard.tscn
