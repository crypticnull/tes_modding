@echo off
title TES Modding - Claude Code
cd /d "X:\MODDING"
echo Resuming the TES modding session in X:\MODDING ...
echo.
claude --continue
if errorlevel 1 (
  echo.
  echo No session to continue. Opening the picker instead.
  claude --resume
)
