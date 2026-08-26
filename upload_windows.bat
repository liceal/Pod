@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_windows.ps1" %*
pause
