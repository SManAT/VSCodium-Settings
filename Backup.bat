@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VSCodiumSync.ps1" -Action Backup -BackupPath "%~dp0VSCodium-Backup"
pause
