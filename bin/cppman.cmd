@echo off
setlocal

set "CPPMAN_WSL_PYTHONPATH=/mnt/c/Users/rodri/scoop/apps/python311/current/Lib/site-packages"
set "CPPMAN_WSL_BRIDGE=/mnt/c/Users/rodri/AppData/Local/nvim/bin/cppman_bridge.py"

wsl.exe -e env PYTHONPATH=%CPPMAN_WSL_PYTHONPATH% python3 %CPPMAN_WSL_BRIDGE% %*
