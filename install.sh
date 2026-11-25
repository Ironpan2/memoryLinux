#!/bin/bash
# memoryLinux installer — reproduces the known-working local setup.
#
# What this builds:
#   ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-1/   (patched)
#   ~/Games/roblox-memory/                                     (game dir + prefix)
#   ~/.local/share/umu/umu-run                                 (umu-launcher)
#   ~/.local/share/applications/roblox-memory.desktop          (roblox-player:// handler)
#
# Idempotent. Run again to repair.

set -euo pipefail

INSTALL_DIR="$HOME/Games/roblox-memory"
PROTON_VER="GE-Proton11-1"
PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${PROTON_VER}/${PROTON_VER}.tar.gz"
PROTON_SHA="ce6dd663ea01725a31805ed5c165723a253cdf0945a6642907330742ae2de5e4"
PROTON_DIR="$HOME/.local/share/Steam/compatibilitytools.d/${PROTON_VER}"
UMU_DIR="$HOME/.local/share/umu"
WEBVIEW2_URL="https://go.microsoft.com/fwlink/p/?LinkId=2124703"
ROBLOX_INSTALLER_URL="https://www.roblox.com/download/client"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
ASSETS="$REPO_ROOT/flatpak/src"       # the .reg files + patch script live here

say() { printf '\n== %s ==\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ----------------------------------------------------------------------
say "0. checking prerequisites"
need curl
need git
need tar
need bwrap    || die "install bubblewrap (apt/dnf/pacman install bubblewrap)"
need python3
need xdg-mime
need update-desktop-database
need cabextract    # winetricks dotnet48 needs this to unpack the MSI
need unzip         # winetricks also uses this
if ! python3 -c "import lief" 2>/dev/null; then
  say "installing python3 lief in a user venv (~/.local/share/memoryLinux/venv)"
  mkdir -p "$HOME/.local/share/memoryLinux"
  python3 -m venv "$HOME/.local/share/memoryLinux/venv"
  "$HOME/.local/share/memoryLinux/venv/bin/pip" -q install lief
  PYTHON="$HOME/.local/share/memoryLinux/venv/bin/python3"
else
  PYTHON=python3
fi

mkdir -p "$INSTALL_DIR" "$PROTON_DIR" "$UMU_DIR" "$(dirname "$PROTON_DIR")"

# ----------------------------------------------------------------------
say "1. GE-Proton ${PROTON_VER}"
if [ ! -f "$PROTON_DIR/proton" ]; then
  tarball="$INSTALL_DIR/${PROTON_VER}.tar.gz"
  if [ ! -f "$tarball" ] || ! echo "${PROTON_SHA}  ${tarball}" | sha256sum -c --status 2>/dev/null; then
    curl -fL --progress-bar -o "$tarball" "$PROTON_URL"
    echo "${PROTON_SHA}  ${tarball}" | sha256sum -c --status || die "proton sha mismatch"
  fi
  tar -xzf "$tarball" -C "$(dirname "$PROTON_DIR")"
  rm -f "$tarball"
else
  echo "already present"
fi

# ----------------------------------------------------------------------
say "2. patching kernelbase.dll (SetProcessValidCallTargets stub)"
KB="$PROTON_DIR/files/lib/wine/x86_64-windows/kernelbase.dll"
if [ ! -f "$KB.orig" ]; then
  cp "$KB" "$KB.orig"
  chmod u+w "$KB"
  "$PYTHON" "$ASSETS/patch-kernelbase.py" "$KB.orig" "$KB.new"
  mv "$KB.new" "$KB"
  chmod a-w "$KB"
else
  echo "already patched (backup exists)"
fi

# ----------------------------------------------------------------------
say "3. umu-launcher"
UMU_RUN="$UMU_DIR/umu-run"
if [ ! -x "$UMU_RUN" ]; then
  tmp="$(mktemp -d)"
  umu_tag=$(curl -fsSL https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest \
            | grep -oE '"tag_name":\s*"[^"]+"' | head -1 | cut -d'"' -f4)
  : "${umu_tag:=1.4.1}"
  tar_url=$(curl -fsSL "https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/tags/${umu_tag}" \
            | grep -oE '"browser_download_url":\s*"[^"]+Zipapp\.tar"' | head -1 | cut -d'"' -f4)
  if [ -n "$tar_url" ]; then
    curl -fL --progress-bar -o "$tmp/umu.tar" "$tar_url"
    tar -xf "$tmp/umu.tar" -C "$UMU_DIR"
  else
    # Fallback: pip-install umu-launcher and link its umu-run entrypoint.
    "$PYTHON" -m pip install --user umu-launcher || die "could not fetch umu-launcher"
    ln -sf "$HOME/.local/bin/umu-run" "$UMU_RUN"
  fi
  rm -rf "$tmp"
else
  echo "already present"
fi

# ----------------------------------------------------------------------
say "4. bubblewrap wrapper script (umu.sh)"
cat > "$INSTALL_DIR/umu.sh" <<EOSH
#!/bin/bash
# Run a Windows program inside the isolated Roblox/memory Proton prefix.
#   ~/Games/roblox-memory/umu.sh <program.exe|winecmd> [args...]
BASE="\$(cd "\$(dirname "\$0")" && pwd)"
H=\$HOME
RT=\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}
PROTON="$PROTON_DIR"
UMU="$UMU_RUN"
mkdir -p "\$BASE/home-cache"

args=(
  --ro-bind / /
  --dev-bind /dev /dev
  --proc /proc
  --tmpfs /tmp
  --tmpfs "\$H"
  --bind "\$BASE" "\$BASE"
  --bind "$UMU_DIR" "$UMU_DIR"
  --bind "\$BASE/home-cache" "\$H/.cache"
  --ro-bind "\$PROTON" "\$PROTON"
  --ro-bind "\$UMU" "\$UMU"
  --tmpfs "\$RT"
  --die-with-parent --new-session
  --setenv HOME "\$H"
)
[ -d /tmp/.X11-unix ] && args+=(--ro-bind /tmp/.X11-unix /tmp/.X11-unix)
[ -n "\${XAUTHORITY:-}" ] && [ -e "\$XAUTHORITY" ] && args+=(--ro-bind "\$XAUTHORITY" "\$XAUTHORITY")
for s in "\${WAYLAND_DISPLAY:-wayland-0}" pipewire-0 pulse; do
  [ -e "\$RT/\$s" ] && args+=(--bind "\$RT/\$s" "\$RT/\$s")
done

export WINEPREFIX="\$BASE/pfx"
export PROTONPATH="\$PROTON"
export GAMEID=umu-roblox-memory
export STORE=none
export PROTON_ENABLE_WAYLAND=0
export DXVK_LOG_LEVEL=none
export WINEDEBUG=-all
export UMU_RUNTIME_UPDATE=0
unset DBUS_SESSION_BUS_ADDRESS DBUS_SYSTEM_BUS_ADDRESS
export SDL_VIDEODRIVER=x11
exec bwrap "\${args[@]}" "\$UMU" "\$@"
EOSH
chmod +x "$INSTALL_DIR/umu.sh"

# ----------------------------------------------------------------------
say "5. Roblox installer + WebView2 bootstrapper"
RBX_INST="$INSTALL_DIR/RobloxPlayerInstaller.exe"
WV2_INST="$INSTALL_DIR/MicrosoftEdgeWebview2Setup.exe"
[ -f "$RBX_INST" ] || curl -fL --progress-bar -o "$RBX_INST" "$ROBLOX_INSTALLER_URL"
[ -f "$WV2_INST" ] || curl -fL --progress-bar -o "$WV2_INST" "$WEBVIEW2_URL"

# ----------------------------------------------------------------------
say "6. picking memory.exe"
pick_memory() {
  if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --title="Select memory.exe" \
           --file-filter='memory.exe | *.exe' --file-filter='All files | *' 2>/dev/null
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --title "Select memory.exe" --getopenfilename "$HOME" '*.exe'
  else
    read -r -p "Path to your memory.exe: " p
    printf '%s\n' "$p"
  fi
}
if [ -f "$INSTALL_DIR/memory.exe" ]; then
  echo "memory.exe already in $INSTALL_DIR — keeping it (re-run with INSTALL_PICK=1 to replace)"
fi
if [ ! -f "$INSTALL_DIR/memory.exe" ] || [ "${INSTALL_PICK:-0}" = "1" ]; then
  src=$(pick_memory) || die "no memory.exe chosen"
  [ -f "$src" ] || die "not a file: $src"
  cp -- "$src" "$INSTALL_DIR/memory.exe"
fi

# ----------------------------------------------------------------------
say "7. initializing prefix + installing Roblox"
cd "$INSTALL_DIR"
# A no-op launch forces the prefix to spawn so later reg imports work.
./umu.sh wineboot -u 2>&1 | tail -5 || true
# Make sure the patched kernelbase overrides the one Proton copied into pfx.
if [ -f "$INSTALL_DIR/pfx/drive_c/windows/system32/kernelbase.dll" ]; then
  cp -f "$KB" "$INSTALL_DIR/pfx/drive_c/windows/system32/kernelbase.dll"
fi
./umu.sh "$RBX_INST" /S 2>&1 | tail -10 || true
for i in $(seq 1 90); do
  ver=$(ls "$INSTALL_DIR/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions/" 2>/dev/null | head -1 || true)
  [ -n "$ver" ] && break
  sleep 1
done
[ -n "$ver" ] || die "Roblox client did not install — check network / try again"
echo "installed Roblox version: $ver"

# ----------------------------------------------------------------------
say "8a. installing .NET Framework 4.8 via winetricks (needed by memory.exe)"
# memory.exe is a ConfuserEx-packed .NET Framework 4 program. Its metadata
# uses the #Schema stream that Wine Mono and system Mono don't implement
# ('Unknown heap type: #Schema'). Real .NET 4.8 handles it.
WT="$INSTALL_DIR/winetricks"
[ -x "$WT" ] || { curl -fL -o "$WT" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks && chmod +x "$WT"; }
if [ ! -f "$INSTALL_DIR/pfx/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/mscoreei.dll" ]; then
  # Point winetricks at our prefix + wine binary; run non-interactively.
  WINE="$PROTON_DIR/files/bin/wine" \
  WINESERVER="$PROTON_DIR/files/bin/wineserver" \
  WINEPREFIX="$INSTALL_DIR/pfx" \
  WINETRICKS_LATEST_VERSION_CHECK=disabled \
  "$WT" -q --force dotnet48 2>&1 | tail -15 || echo "(winetricks dotnet48 may have reported errors — often cosmetic; continuing)"
else
  echo ".NET 4.8 already present"
fi

# ----------------------------------------------------------------------
say "8b. installing WebView2"
./umu.sh "$WV2_INST" /silent /install 2>&1 | tail -5 || true

# ----------------------------------------------------------------------
say "9. applying registry tweaks"
for reg in win10.reg mouse-fix.reg webview2-flags.reg roblox-uri.reg; do
  [ -f "$ASSETS/$reg" ] || continue
  cp "$ASSETS/$reg" "$INSTALL_DIR/$reg"
  ./umu.sh regedit /S "Z:$INSTALL_DIR/$reg" 2>&1 | tail -3 || true
done

# ----------------------------------------------------------------------
say "10. DXVK stability conf"
cp "$ASSETS/dxvk.conf" \
   "$INSTALL_DIR/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions/$ver/dxvk.conf"

# ----------------------------------------------------------------------
say "11. running memory.exe (DLL swap)"
./umu.sh memory.exe 2>&1 | tail -5 || true
# memory.exe spawns Roblox; wait for it then kill both so we exit cleanly.
sleep 20
pkill -f "RobloxPlayerBeta|memory.exe|wineserver.*roblox-memory" 2>/dev/null || true

# ----------------------------------------------------------------------
say "12. registering roblox-player:// handler on host"
cat > "$INSTALL_DIR/launch-uri.sh" <<EOSH
#!/bin/bash
BASE=\$(cd "\$(dirname "\$0")" && pwd)
URI=\$1
exec "\$BASE/umu.sh" \\
  'C:\\users\\steamuser\\AppData\\Local\\Roblox\\Versions\\$ver\\RobloxPlayerBeta.exe' \\
  "\$URI"
EOSH
chmod +x "$INSTALL_DIR/launch-uri.sh"

APPS="$HOME/.local/share/applications"
mkdir -p "$APPS"
cat > "$APPS/roblox-memory.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Roblox (memory, Proton)
Exec=$INSTALL_DIR/launch-uri.sh %u
Terminal=false
MimeType=x-scheme-handler/roblox;x-scheme-handler/roblox-player;
Categories=Game;
EOF
update-desktop-database "$APPS" >/dev/null 2>&1 || true
xdg-mime default roblox-memory.desktop x-scheme-handler/roblox-player 2>&1 | grep -v qtpaths || true
xdg-mime default roblox-memory.desktop x-scheme-handler/roblox        2>&1 | grep -v qtpaths || true

# ----------------------------------------------------------------------
cat <<DONE

================================================================
  install complete

  TO PLAY:
    1. open roblox.com in your normal browser
    2. log in, click Play on any game
    3. your browser offers 'Roblox (memory, Proton)' — accept

  To re-pick memory.exe later:
    INSTALL_PICK=1 $0

  To wipe and start over:
    rm -rf $INSTALL_DIR
================================================================

DONE
