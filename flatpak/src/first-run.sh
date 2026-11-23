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

# memory.exe only swaps DLLs into an already-installed Roblox client, so
# we need to run Roblox's own bootstrapper first. Fetch it fresh each
# first-run so we land on the current channel.
INSTALLER="$PREFIX/RobloxPlayerInstaller.exe"
if [ ! -f "$PREFIX/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions" ] || \
   [ -z "$(ls "$PREFIX/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions" 2>/dev/null)" ]; then
  echo ">> downloading RobloxPlayerInstaller"
  curl -fL --retry 3 -o "$INSTALLER" https://www.roblox.com/download/client
  echo ">> installing Roblox client (this takes a minute)"
  python3 "$PROTON_DIR/proton" waitforexitandrun "$INSTALLER" /S || true
  # Wait up to 90s for the Versions/ folder to populate.
  for i in $(seq 1 90); do
    ver=$(ls "$PREFIX/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions/" 2>/dev/null | head -1)
    [ -n "$ver" ] && { echo ">> roblox installed: $ver"; break; }
    sleep 1
  done
fi

echo ">> first-run setup complete"
