@echo off
chcp 65001 > nul
cd /d "%~dp0"
node --test tests/catalog-ui.test.mjs
if errorlevel 1 exit /b %errorlevel%
if exist "venv\Scripts\python.exe" (
    "%~dp0venv\Scripts\python.exe" -m unittest discover -s tests
) else (
    python -m unittest discover -s tests
)