@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -ExecutionPolicy Bypass -File "%~dp0skills.ps1" %*
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0skills.ps1" %*
)
pause
