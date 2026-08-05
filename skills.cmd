@echo off
setlocal

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "POWERSHELL_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
)
if not defined POWERSHELL_EXE (
    for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined POWERSHELL_EXE set "POWERSHELL_EXE=%%I"
)
if not defined POWERSHELL_EXE (
    echo PowerShell 7+ (pwsh) is required. Install it from https://aka.ms/powershell 1>&2
    exit /b 9009
)
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
exit /b %EXIT_CODE%
