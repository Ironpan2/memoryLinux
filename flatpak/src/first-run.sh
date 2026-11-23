#!/bin/bash
# First-run setup: unpack Proton, patch kernelbase, build prefix, install
# WebView2, apply registry tweaks for login + mouse grab + URI handlers.
set -eu
PROTON_TAR=$1
PROTON_DIR=$2
PREFIX=$3
WEBVIEW2_EXE=$4
LIBEXEC=$5

mkdir -p "$PROTON_DIR" "$PREFIX"
echo ">> extracting Proton"
tar -xzf "$PROTON_TAR" -C "$PROTON_DIR" --strip-components=1

KB=$PROTON_DIR/files/lib/wine/x86_64-windows/kernelbase.dll
if [ ! -f "$KB.orig" ]; then
  echo ">> patching kernelbase.dll (SetProcessValidCallTargets stub)"
  cp "$KB" "$KB.orig"
  python3 "$LIBEXEC/patch-kernelbase.py" "$KB.orig" "$KB"
fi

export STEAM_COMPAT_CLIENT_INSTALL_PATH=$PREFIX
export STEAM_COMPAT_DATA_PATH=$PREFIX
export WINEPREFIX=$PREFIX/pfx
export PROTONPATH=$PROTON_DIR
export WINEDEBUG=-all

echo ">> initializing prefix"
python3 "$PROTON_DIR/proton" waitforexitandrun /app/libexec/roblox-memory/_true.sh || true
# Copy the patched kernelbase into the newly-minted prefix too (Proton's prefix
# init copied the original one into drive_c/windows/system32).
if [ -f "$PREFIX/pfx/drive_c/windows/system32/kernelbase.dll" ]; then
  cp "$KB" "$PREFIX/pfx/drive_c/windows/system32/kernelbase.dll"
fi

echo ">> installing WebView2"
python3 "$PROTON_DIR/proton" waitforexitandrun "$WEBVIEW2_EXE" /silent /install || true

echo ">> applying registry: win10 fingerprint + mouse grab + webview flags + uri handler"
for reg in win10.reg mouse-fix.reg webview2-flags.reg roblox-uri.reg; do
  if [ -f "$LIBEXEC/$reg" ]; then
    python3 "$PROTON_DIR/proton" waitforexitandrun regedit /S "Z:$LIBEXEC/$reg" || true
  fi
done

echo ">> first-run setup complete"
