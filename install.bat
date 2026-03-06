@echo off
chcp 65001 > nul
set "ZIP=%~dp0data_scripts.zip"
set "DIR=%~dp0data_scripts_zip"

echo ===========================================
echo   Менеджер оновлення Rotwood (ПЕРЕМІЩЕННЯ)
echo ===========================================
echo.
echo [1] Оновлення основного архіву (data_scripts.zip)
echo [2] Встановлення моду в AppData (uklocale)
echo [3] Виконати все разом
echo.
set /p "main_choice=Виберіть дію (1-3): "

if "%main_choice%"=="2" goto :appdata_setup
if "%main_choice%"=="3" (set "DO_BOTH=1" & goto :zip_update)

:zip_update
echo.
echo [1/2] Оновлення архіву...
powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip=[System.IO.Compression.ZipFile]::Open('%ZIP%', 'Update'); Get-ChildItem -Path '%DIR%' -Recurse | Where-Object {!$_.PSIsContainer} | ForEach-Object {$rel=$_.FullName.Substring('%DIR%'.Length+1).Replace('\','/'); $exist=$zip.Entries | Where-Object {$_.FullName -eq $rel}; if($exist){$exist.Delete()}; [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel)}; $zip.Dispose();"
if not defined DO_BOTH goto :end

:appdata_setup
echo.
echo [2/2] Налаштування AppData...
echo Виберіть версію гри:
echo [1] Rotwood (Реліз)
echo [2] Rotwood_preview (Бета)
set /p "ver_choice=Ваш вибір (1-2): "

if "%ver_choice%"=="1" (set "TARGET=Rotwood") else (set "TARGET=Rotwood_preview")
set "KLEI_PATH=%APPDATA%\Klei\%TARGET%"

if not exist "%KLEI_PATH%" (
    echo [!] Помилка: Папку %TARGET% не знайдено!
    pause & exit /b
)

:: Пошук папок: steam-ID або просто цифри
powershell -NoProfile -Command "$dirs = Get-ChildItem -Path '%KLEI_PATH%' -Directory | Where-Object { $_.Name -match '^steam-\d+$' -or $_.Name -match '^\d+$' }; if ($dirs.Count -eq 0) { Write-Host 'Папок акаунтів не знайдено!' -ForegroundColor Red; exit }; if ($dirs.Count -eq 1) { $picked = $dirs[0] } else { Write-Host 'Виберіть акаунт:'; for ($i=0; $i -lt $dirs.Count; $i++) { Write-Host \"[$($i+1)] $($dirs[$i].Name)\" }; $idx = [int](Read-Host 'Вибір') - 1; $picked = $dirs[$idx] }; $modPath = Join-Path $picked.FullName 'mods\uklocale'; if (!(Test-Path $modPath)) { New-Item -ItemType Directory -Path $modPath -Force | Out-Null }; \"TARGET_MOD_PATH=$modPath\" | Out-File -FilePath '%TEMP%\modpath.tmp' -Encoding ascii"

if not exist "%TEMP%\modpath.tmp" (
    echo [!] Не вдалося знайти папку steam-ID.
    pause & exit /b
)

for /f "usebackq delims=" %%i in ("%TEMP%\modpath.tmp") do set "%%i"
del "%TEMP%\modpath.tmp"

echo Переміщення файлів у: %TARGET_MOD_PATH%

:: Переміщення папок (/MOVE видаляє джерело після копіювання)
if exist "%~dp0fonts" robocopy "%~dp0fonts" "%TARGET_MOD_PATH%\fonts" /E /MOVE > nul
if exist "%~dp0localizations" robocopy "%~dp0localizations" "%TARGET_MOD_PATH%\localizations" /E /MOVE > nul
if exist "%~dp0scripts" robocopy "%~dp0scripts" "%TARGET_MOD_PATH%\scripts" /E /MOVE > nul

:: Переміщення окремих файлів
move /y "%~dp0crowdin.yml" "%TARGET_MOD_PATH%\" > nul 2>&1
move /y "%~dp0LICENSE" "%TARGET_MOD_PATH%\" > nul 2>&1
move /y "%~dp0modicon.png" "%TARGET_MOD_PATH%\" > nul 2>&1
move /y "%~dp0modinfo.lua" "%TARGET_MOD_PATH%\" > nul 2>&1
move /y "%~dp0modmain.lua" "%TARGET_MOD_PATH%\" > nul 2>&1
move /y "%~dp0README.md" "%TARGET_MOD_PATH%\" > nul 2>&1

echo Переміщення завершено! Файли тепер в AppData.
goto :end

:end
echo.
echo ---------------------------------------
echo Готово! Все налаштовано.
pause