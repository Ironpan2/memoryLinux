#!/bin/bash
# Prompt the user for memory.exe. Prefer zenity if installed; otherwise ask
# on stdin for a path. Prints the chosen absolute path on stdout, non-zero
# exit on cancel.
set -eu
msg="Pick the memory.exe you want to use.

It will be run once inside the sandbox to install its DLLs
into the Roblox prefix. The file is not uploaded anywhere."

if command -v zenity >/dev/null 2>&1; then
  path=$(zenity --file-selection \
                --title="Select memory.exe" \
                --file-filter='memory.exe | *.exe' \
                --file-filter='All files | *') || exit 1
elif command -v kdialog >/dev/null 2>&1; then
  path=$(kdialog --title "Select memory.exe" --getopenfilename "$HOME" "*.exe") || exit 1
else
  printf '%s\n' "$msg" >&2
  read -r -p "Path to memory.exe: " path
  [ -n "$path" ] || exit 1
fi

[ -f "$path" ] || { echo "not a file: $path" >&2; exit 1; }
case $(file -b "$path" 2>/dev/null) in
  *PE32*|*executable*) : ;;
  *) echo "warning: doesn't look like a Windows PE binary: $path" >&2 ;;
esac
printf '%s\n' "$path"
