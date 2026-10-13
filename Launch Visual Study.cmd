@echo off
rem Launch the isolated visual study, regardless of the scene open in Godot.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\visual_study\Launch.ps1"
if errorlevel 1 pause
