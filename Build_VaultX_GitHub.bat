@echo off
setlocal EnableExtensions
title VaultX - Push and Build on GitHub

cd /d "%~dp0"

echo ==================================================
echo   VaultX - GitHub Build Launcher
echo ==================================================
echo.

if not exist ".git" (
    echo [ERROR] This BAT file must be inside the VaultX Git repository folder.
    echo Expected folder example:
    echo C:\Users\Pc\Desktop\VaultX1
    echo.
    pause
    exit /b 1
)

where git >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Git is not installed or is not available in PATH.
    echo.
    pause
    exit /b 1
)

echo [1/5] Checking repository...
git status --short
echo.

echo [2/5] Adding all changes...
git add -A
if errorlevel 1 goto :fail

echo [3/5] Creating commit when changes exist...
git diff --cached --quiet
if errorlevel 1 (
    for /f "tokens=1-4 delims=/ " %%a in ("%date%") do set BUILD_DATE=%%d-%%b-%%c
    for /f "tokens=1-2 delims=:." %%a in ("%time%") do set BUILD_TIME=%%a-%%b
    git commit -m "VaultX build %BUILD_DATE% %BUILD_TIME%"
    if errorlevel 1 goto :fail
) else (
    echo No new files to commit.
)

echo.
echo [4/5] Pushing branch main to GitHub...
git push origin main
if errorlevel 1 goto :fail

echo.
echo [5/5] Triggering or opening GitHub Actions...

where gh >nul 2>&1
if not errorlevel 1 (
    gh workflow run ios-build.yml --ref main >nul 2>&1
    if not errorlevel 1 (
        echo GitHub Actions workflow was triggered.
    ) else (
        echo Push completed. The workflow should start automatically.
    )
) else (
    echo Push completed. The workflow should start automatically.
)

start "" "https://github.com/9bh/Phone1/actions"

echo.
echo ==================================================
echo SUCCESS: Files were pushed to GitHub.
echo Check these three jobs:
echo   1. Build VaultX for iOS Simulator
echo   2. Run VaultXTests
echo   3. Create Unsigned iPhone IPA
echo ==================================================
echo.
pause
exit /b 0

:fail
echo.
echo ==================================================
echo [ERROR] The operation failed.
echo Review the Git message shown above.
echo ==================================================
echo.
pause
exit /b 1
