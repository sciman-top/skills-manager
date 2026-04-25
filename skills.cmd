@echo off
setlocal

if not defined CODEX_ALLOW_WINDOWS_POWERSHELL (
    if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        set "POWERSHELL_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
    )
    if not defined POWERSHELL_EXE (
        for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined POWERSHELL_EXE set "POWERSHELL_EXE=%%I"
    )
)
if not defined POWERSHELL_EXE (
    set "POWERSHELL_EXE=powershell.exe"
)
"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0skills.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
pause
exit /b %EXIT_CODE%
