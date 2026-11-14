@echo off
rem Chay LDFix voi quyen Admin (can khi LDPlayer cai trong Program Files)
powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0LDFix.ps1\"'"
