@echo off

set "fileUrl=https://raw.githubusercontent.com/MaksymKurny/Rotwood-UA/main_beta/data_scripts_zip/localizations/uk.po"
set "fileName=uk.po"
set "localizationsFolder=localizations"

curl -L -o "%fileName%" "%fileUrl%" >nul 2>&1

if %errorlevel% equ 0 (
    if not exist "%localizationsFolder%" (
        mkdir "%localizationsFolder%"
    )
    move /Y "%fileName%" "%localizationsFolder%\%fileName%" >nul 2>&1
)
