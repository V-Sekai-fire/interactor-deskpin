@echo off
rem Runs the tray app in this console. Close the console or use the tray Quit item.
cd /d "%~dp0"
elixir --erl "-noinput" -S mix run --no-halt
