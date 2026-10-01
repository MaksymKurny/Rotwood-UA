@echo off
rem Rotwood-UA: update translation from GitHub, then start the game.
rem Steam launch option:  "<path to Rotwood>\update_ukua.bat" %command% --dlc ukua
rem If an update fails (no internet etc.) the game still starts with the current translation.
if exist "%~dp0update_ukua.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update_ukua.ps1" >nul 2>&1
)
%*
