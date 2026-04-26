@echo off
chcp 65001 >nul
title Cloudreve Downloader v3.0
cd /d "%~dp0"
echo ========================================
echo   Cloudreve Downloader v3.0
echo ========================================
echo.

:: Check PowerShell
powershell -Command "Get-Host" >nul 2>&1
if errorlevel 1 (
    echo [ERR] PowerShell not found!
    pause
    exit /b 1
)

:: Check aria2
aria2c --version >nul 2>&1
if errorlevel 1 (
    echo [WARN] aria2 not found in PATH.
    echo [INFO] Searching for aria2 installation...
    
    :: Try to find aria2 in winget location
    for /f "delims=" %%i in ('powershell -Command "Get-ChildItem -Path \"$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Filter 'aria2c.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName"') do (
        set "ARIA2_PATH=%%~dpi"
    )
    
    if defined ARIA2_PATH (
        echo [OK] Found aria2 at: %ARIA2_PATH%
        set "PATH=%ARIA2_PATH%;%PATH%"
    ) else (
        echo [ERR] aria2 not found!
        echo [INFO] Please install aria2:
        echo        winget install aria2.aria2
        echo.
        pause
        exit /b 1
    )
)

:: Run PowerShell script with -NoExit to keep window open
echo [INFO] Starting download tool...
echo.
powershell -NoExit -ExecutionPolicy Bypass -File "cloudreve-downloader.ps1"
