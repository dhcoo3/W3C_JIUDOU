@echo off
setlocal EnableExtensions

for %%I in ("%~dp0.") do set "ROOT=%%~fI"
set "PROJECT_ROOT=%ROOT%\Build"
set "EXCEL_ROOT=%ROOT%\excelCfg"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\generate_lua_config.ps1" -Root "%PROJECT_ROOT%" -ExcelRoot "%EXCEL_ROOT%"
exit /b %ERRORLEVEL%
