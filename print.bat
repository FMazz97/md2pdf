@echo off
rem Double-click launcher: asks for the project folder and creates the PDF inside it.
rem A folder dropped onto this file skips the selection dialog.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "build-pdf.ps1" -Project "%~1"
rem The window closes on success; on failure it stays open so the message can be read.
if errorlevel 1 (
  echo.
  echo ERROR: PDF generation failed.
  pause
)
