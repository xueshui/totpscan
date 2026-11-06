@echo off
rem 一键构建转发脚本（DevEco Studio 打开工程后可能用官方 wrapper 覆盖本文件）。
rem 用法：hvigorw.bat [assembleHap] [module] [product]
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" %*
exit /b %ERRORLEVEL%
