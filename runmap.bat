@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "XLIK=%ROOT%Build\tools\xlik.exe"
set "MODE=%~1"
if "%MODE%"=="" set "MODE=-t!"

if not exist "%XLIK%" (
    echo [error] xlik.exe not found: "%XLIK%"
    exit /b 1
)

echo [1/2] Generating Lua config...
call "%ROOT%generate_lua_config.bat"
if errorlevel 1 (
    echo [error] Lua config generation failed.
    exit /b 1
)

echo [2/2] Running xlik %MODE%...
pushd "%ROOT%Build"
"%XLIK%" run JiuDou %MODE%
set "EXIT_CODE=%ERRORLEVEL%"
popd
endlocal & exit /b %EXIT_CODE%
