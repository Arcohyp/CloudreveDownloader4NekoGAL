@echo off
chcp 65001 >nul
title Cloudreve Downloader v3.2
cd /d "%~dp0"
echo ========================================
echo   Cloudreve Downloader v3.2.0
echo ========================================
echo.

:: Check PowerShell
powershell -Command "Get-Host" >nul 2>nul
if errorlevel 1 (
    echo [ERR] PowerShell not found!
    pause
    exit /b 1
)

:: Run PowerShell script with -NoExit to keep window open
echo [INFO] Starting download tool...
echo.
powershell -NoExit -ExecutionPolicy Bypass -File "cloudreve-downloader.ps1"
