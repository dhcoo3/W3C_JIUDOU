@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"

if "%~1"=="" (
    echo.
    echo Usage:
    echo   import_model.bat "model-folder"
    echo   import_model.bat "model-folder" -AssetStem "CustomName"
    echo.
    echo This imports the model and textures directly into formal assets.
    echo No model preview is performed.
    echo.
    exit /b 2
)

set "SOURCE=%~1"
set "OPTIONS="
shift

:collect_options
if "%~1"=="" goto run_import
if /I "%~1"=="-Promote" (
    echo Note: -Promote is no longer required; direct formal import is enabled.
    shift
    goto collect_options
)
if /I "%~1"=="-NoPreview" (
    shift
    goto collect_options
)
if /I "%~1"=="-AssetStem" (
    if "%~2"=="" (
        echo Missing value for -AssetStem.
        exit /b 2
    )
    set "OPTIONS=%OPTIONS% -AssetStem \"%~2\""
    shift
    shift
    goto collect_options
)
echo Unknown option: %~1
exit /b 2

:run_import
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\import_model.ps1" -Source "%SOURCE%"%OPTIONS%
set "EXIT_CODE=%ERRORLEVEL%"

endlocal & exit /b %EXIT_CODE%