@echo off
setlocal
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -File "%~dp0bootstrap.ps1"
if errorlevel 1 echo Installation stopped. Read the message above before retrying.
pause
