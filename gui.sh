#!/bin/bash
# memoryLinux GUI helper — zenity-based wrapper around install.sh.
# One dialog, every action.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/Games/roblox-memory"
VERS_DIR="$INSTALL_DIR/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions"
DESKTOP="$HOME/.local/share/applications/roblox-memory.desktop"

if ! command -v zenity >/dev/null 2>&1; then
  echo "zenity is not installed. install it with your package manager, or use ./install.sh from a terminal." >&2
  exit 1
fi
if [ ! -f "$HERE/install.sh" ]; then
  zenity --error --title="memoryLinux" --text="gui.sh must live next to install.sh (inside the cloned memoryLinux repo)."
  exit 1
fi

# ------------------------------------------------------------------ util

status_text() {
  local installed="no" current="(none)" mem="no" handler="no" cnt=0
  [ -f "$INSTALL_DIR/umu.sh" ] && installed="yes"
  [ -d "$VERS_DIR" ] && cnt=$(ls -1 "$VERS_DIR" 2>/dev/null | grep -c '^version-')
  [ "$cnt" -gt 0 ] && current=$(ls -1t "$VERS_DIR" 2>/dev/null | grep '^version-' | head -1)
  [ -f "$INSTALL_DIR/memory.exe" ] && mem="yes ($(stat -c '%s bytes, %y' "$INSTALL_DIR/memory.exe" | cut -d. -f1))"
  [ -f "$DESKTOP" ] && handler="yes"
  cat <<EOF
<b>memoryLinux status</b>

installed:        $installed
roblox versions:  $cnt installed
newest version:   $current
memory.exe:       $mem
URI handler:      $handler
install dir:      $INSTALL_DIR
EOF
}

run_with_progress() {
  # $1 = title, rest = command. Streams the command's stdout/stderr into
  # a zenity progress dialog; opens a terminal log viewer at the end.
  local title="$1"; shift
  local log; log=$(mktemp -t memgui.XXXXXX.log)
  (
    "$@" >>"$log" 2>&1
    echo "__memgui_done__" >>"$log"
  ) &
  local pid=$!
  (
    tail -n 0 -f "$log" 2>/dev/null | while IFS= read -r line; do
      [ "$line" = "__memgui_done__" ] && { echo 100; break; }
      case "$line" in
        "== "*) printf '# %s\n' "${line#== }"; printf 'pulsate\n' ;;
        *) : ;;
      esac
    done
  ) | zenity --progress --pulsate --auto-close --no-cancel \
             --title="$title" --text="starting..." --width=500
  wait "$pid" 2>/dev/null
  if ! grep -q "^__memgui_done__$" "$log"; then
    zenity --error --title="$title failed" \
           --text="The script exited abnormally. See the log for details." --width=400
  fi
  zenity --text-info --title="$title — log" --filename="$log" \
         --width=800 --height=600 2>/dev/null
  rm -f "$log"
}

ensure_installed() {
  if [ ! -f "$INSTALL_DIR/umu.sh" ]; then
    zenity --error --title="Not installed" \
      --text="memoryLinux isn't installed yet. Run <b>Install</b> first."
    return 1
  fi
}

# ------------------------------------------------------------------ actions

act_install() {
  zenity --question --title="Install" --width=400 --text=\
"Install memoryLinux?

This downloads ~700MB (GE-Proton + Roblox + WebView2 + .NET 4.8).
You'll be asked to pick your memory.exe at the end." || return
  run_with_progress "Installing" bash "$HERE/install.sh"
}

act_update() {
  ensure_installed || return
  zenity --question --title="Update Roblox" --width=400 --text=\
"Re-run the Roblox installer to update to the newest version, then\nre-apply the memory.exe DLL swap. Takes ~2 minutes." || return
  run_with_progress "Updating Roblox" bash "$HERE/install.sh" --update
}

act_downgrade() {
  ensure_installed || return
  local hint=""
  local hash
  hash=$(zenity --entry --title="Downgrade Roblox" --width=500 --text=\
"Paste a Roblox version hash (hex part only, like <tt>2c6fd5e09aaf4cfa</tt>).

Find valid hashes at:
  • rblx.trade/version
  • rdd.weao.xyz
  • clientsettings.roblox.com API") || return
  hash=${hash#version-}
  [ -n "$hash" ] || { zenity --error --text="No hash entered."; return; }
  run_with_progress "Downgrading to version-$hash" bash "$HERE/install.sh" --downgrade "$hash"
}

act_repick_memory() {
  ensure_installed || return
  zenity --question --title="Re-pick memory.exe" --width=400 --text=\
"Replace the current memory.exe and re-run its installer?" || return
  local src
  src=$(zenity --file-selection --title="Select new memory.exe" \
         --file-filter='memory.exe | *.exe' --file-filter='All files | *') || return
  [ -f "$src" ] || { zenity --error --text="Not a file."; return; }
  cp -- "$src" "$INSTALL_DIR/memory.exe"
  run_with_progress "Reinstalling memory" bash "$HERE/install.sh"
}

act_launch() {
  ensure_installed || return
  [ -x "$INSTALL_DIR/launch-uri.sh" ] || {
    zenity --error --text="launch-uri.sh is missing — re-run Install."
    return
  }
  local uri
  uri=$(zenity --entry --title="Launch URI" --width=600 --text=\
"Paste a roblox-player:// URI from your browser (optional).

Leave blank to just open RobloxPlayerBeta.exe with no join target.") || return
  if [ -z "$uri" ]; then
    # No URI → fire RobloxPlayerBeta.exe directly through umu, newest version.
    local ver; ver=$(ls -1t "$VERS_DIR" 2>/dev/null | grep '^version-' | head -1)
    [ -n "$ver" ] || { zenity --error --text="No Roblox version installed."; return; }
    ( cd "$INSTALL_DIR" && ./umu.sh \
        "C:\\users\\steamuser\\AppData\\Local\\Roblox\\Versions\\$ver\\RobloxPlayerBeta.exe" & )
  else
    ( "$INSTALL_DIR/launch-uri.sh" "$uri" & )
  fi
  zenity --info --title="Launching" --text="Roblox is starting in the sandbox." --timeout=4 &>/dev/null
}

act_prefix_cmd() {
  ensure_installed || return
  local cmd
  cmd=$(zenity --entry --title="Run in prefix" --width=500 --text=\
"Windows command to run inside the sandbox prefix.

Examples:
  winecfg
  regedit
  cmd /c ver") || return
  [ -n "$cmd" ] || return
  ( cd "$INSTALL_DIR" && ./umu.sh $cmd & )
}

act_reset() {
  zenity --question --title="Reset everything?" --width=450 --text=\
"<b>This deletes:</b>
  • ~/Games/roblox-memory/  (the whole prefix + memory.exe)
  • ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-1
  • ~/.local/share/applications/roblox-memory.desktop

Continue?" || return
  rm -rf "$INSTALL_DIR"
  rm -rf "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-1"
  rm -f  "$DESKTOP"
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  zenity --info --title="Reset done" --text="All removed. Run Install to set back up."
}

act_status() {
  zenity --info --title="memoryLinux status" --width=500 \
         --text="$(status_text)"
}

# ------------------------------------------------------------------ menu

while :; do
  choice=$(zenity --list --title="memoryLinux" --width=560 --height=440 \
    --text="What do you want to do?" \
    --column="Action" --column="Description" \
    "Install"           "Full install (GE-Proton, Roblox, WebView2, .NET 4.8, URI handler, memory.exe)" \
    "Update Roblox"     "Fetch newest Roblox client + re-apply memory.exe DLL swap" \
    "Downgrade Roblox"  "Install a specific Roblox version by hash" \
    "Re-pick memory.exe" "Replace the memory.exe and re-run its installer" \
    "Launch Roblox"     "Open Roblox directly or with a pasted roblox-player:// URI" \
    "Run in prefix"     "Execute a Windows command inside the sandbox (winecfg, regedit, …)" \
    "Status"            "Show what's installed and where" \
    "Reset everything"  "Nuke the prefix, Proton, and URI handler" \
    "Quit"              "Close this helper") || break
  case "$choice" in
    Install)             act_install ;;
    "Update Roblox")     act_update ;;
    "Downgrade Roblox")  act_downgrade ;;
    "Re-pick memory.exe")act_repick_memory ;;
    "Launch Roblox")     act_launch ;;
    "Run in prefix")     act_prefix_cmd ;;
    Status)              act_status ;;
    "Reset everything")  act_reset ;;
    Quit|"")             break ;;
  esac
done
