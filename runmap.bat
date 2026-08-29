@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if not defined W2L_EXE set "W2L_EXE=C:\Users\Administrator\Documents\War3Work\tools\w3x2lni\2.7.3\w2l.exe"
if not defined YDWE_CONFIG_EXE (
    for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$launcher = 'G:\KKWE' + [char]0x63D2 + [char]0x4EF6 + '\bin\YDWEConfig.exe'; [Console]::Write($launcher)"`) do set "YDWE_CONFIG_EXE=%%I"
)
set "PROJECT_ROOT=%ROOT%Build"
set "TEST_MAP=%PROJECT_ROOT%\JiuDouTest.w3x"
set "STAGING_TEST_MAP=%ROOT%JiuDouTest.building.w3x"
set "BACKUP_TEST_MAP=%ROOT%JiuDouTest.previous.w3x"
set "HAS_BACKUP=0"

if not exist "%PROJECT_ROOT%\.w3x" (
    echo [error] LNI project marker not found: "%PROJECT_ROOT%\.w3x"
    exit /b 1
)

if exist "%PROJECT_ROOT%\excelCfg" (
    echo [error] excelCfg must stay outside the Build project: "%PROJECT_ROOT%\excelCfg"
    exit /b 1
)

if not exist "%W2L_EXE%" (
    echo [error] w2l.exe not found: "%W2L_EXE%"
    exit /b 1
)

if not exist "%YDWE_CONFIG_EXE%" (
    echo [error] YDWEConfig.exe not found: "%YDWE_CONFIG_EXE%"
    exit /b 1
)

echo [1/3] Generating Lua config...
call "%ROOT%generate_lua_config.bat"
if errorlevel 1 (
    echo [error] Lua config generation failed.
    exit /b 1
)

echo [2/3] Building test map...
if exist "%STAGING_TEST_MAP%" del /q "%STAGING_TEST_MAP%"
if exist "%BACKUP_TEST_MAP%" del /q "%BACKUP_TEST_MAP%"
if exist "%TEST_MAP%" (
    move /y "%TEST_MAP%" "%BACKUP_TEST_MAP%" >nul
    if errorlevel 1 (
        echo [error] Existing test map could not be staged: "%TEST_MAP%"
        exit /b 1
    )
    set "HAS_BACKUP=1"
)

"%W2L_EXE%" obj "%PROJECT_ROOT%" "%STAGING_TEST_MAP%"
if errorlevel 1 (
    echo [error] Map build failed.
    goto :build_failed
)

if not exist "%STAGING_TEST_MAP%" (
    echo [error] Test map was not generated: "%STAGING_TEST_MAP%"
    goto :build_failed
)

move /y "%STAGING_TEST_MAP%" "%TEST_MAP%" >nul
if errorlevel 1 (
    echo [error] Test map replacement failed.
    goto :build_failed
)

if "%HAS_BACKUP%"=="1" if exist "%BACKUP_TEST_MAP%" del /q "%BACKUP_TEST_MAP%"

echo [3/3] Launching test map...
"%YDWE_CONFIG_EXE%" -launchwar3 -loadfile "%TEST_MAP%"
if errorlevel 1 (
    echo [error] Warcraft III launch failed.
    exit /b 1
)

endlocal
exit /b 0

:build_failed
if exist "%STAGING_TEST_MAP%" del /q "%STAGING_TEST_MAP%"
if "%HAS_BACKUP%"=="1" if not exist "%TEST_MAP%" move /y "%BACKUP_TEST_MAP%" "%TEST_MAP%" >nul
endlocal
exit /b 1
