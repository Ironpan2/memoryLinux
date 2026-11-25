# memoryLinux

Run Roblox + the **memory** executor on Linux via a patched GE-Proton. Single bash installer — no flatpak, no package managers to wrestle with. Mirrors a known-working setup reached end-to-end: Byfron CFG stub, WebView2 for login, `roblox-player://` URI handler so browser-based play works, DXVK stability tuning, X11 pointer-grab for first-person.

`memory.exe` is **not bundled** — the installer prompts for it and you point at your own copy.

---

## Install

### 1. Prerequisites

| Distro             | Install                                                                     |
|--------------------|-----------------------------------------------------------------------------|
| Ubuntu / Debian    | `sudo apt install git curl bubblewrap python3 python3-venv python3-pip zenity xdg-utils desktop-file-utils` |
| Fedora             | `sudo dnf install git curl bubblewrap python3 python3-pip zenity xdg-utils desktop-file-utils`             |
| Arch / Manjaro     | `sudo pacman -S git curl bubblewrap python zenity xdg-utils desktop-file-utils`                            |
| openSUSE           | `sudo zypper install git curl bubblewrap python3 python3-pip zenity xdg-utils desktop-file-utils`          |
| Void               | `sudo xbps-install -S git curl bubblewrap python3 python3-pip zenity xdg-utils desktop-file-utils`         |

### 2. Clone and run the installer

```sh
git clone https://github.com/Ironpan2/memoryLinux
cd memoryLinux
./install.sh
```

What it does:

1. Downloads **GE-Proton 11-1** (~500 MB) to `~/.local/share/Steam/compatibilitytools.d/`.
2. Patches `kernelbase.dll` — adds a no-op `SetProcessValidCallTargets` stub so Byfron stops aborting under Wine.
3. Fetches **umu-launcher** and drops a bubblewrap wrapper at `~/Games/roblox-memory/umu.sh`.
4. Downloads the **Roblox client installer** + **Microsoft Edge WebView2** bootstrapper.
5. Pops a **file picker** asking for your `memory.exe`.
6. Spins up the Wine prefix, installs Roblox, installs WebView2, applies registry tweaks (Win10 fingerprint + X11 pointer grab + WebView2 browser flags).
7. Runs `memory.exe` once to swap the fake `RobloxPlayerBeta.dll` + drop `Mem3API.dll`.
8. Drops a DXVK stability `dxvk.conf` next to RobloxPlayerBeta.
9. Registers `roblox://` and `roblox-player://` handlers on your host so browser Play buttons route into the sandbox.

Install is **idempotent** — re-run to repair.

### 3. Play

1. Open your normal browser, go to [roblox.com](https://roblox.com), log in.
2. Click **Play** on any game.
3. Browser offers *"Roblox (memory, Proton)"* — accept.
4. Game launches under the sandbox with the memory executor overlay active.

Direct URI launch (no browser prompt):
```sh
~/Games/roblox-memory/launch-uri.sh 'roblox-player:1+launchmode:play+gameinfo:...'
```

---

## Maintenance

```sh
# re-pick memory.exe (new build, different file)
INSTALL_PICK=1 ./install.sh

# nuke and start over
rm -rf ~/Games/roblox-memory
rm -rf ~/.local/share/Steam/compatibilitytools.d/GE-Proton11-1
rm    ~/.local/share/applications/roblox-memory.desktop

# just run something inside the prefix (e.g. regedit, winecfg)
~/Games/roblox-memory/umu.sh winecfg
```

---

## Known issues

- **Heavy games can crash with `EXCEPTION_ACCESS_VIOLATION`.** Confirmed via minidump analysis to be inside the executor's own anonymous memory region (same low-16-bit offset across DXVK and WineD3D runs — not a Wine/Proton/DXVK bug). Lower in-game graphics quality or try a newer `memory.exe` build.
- **Captcha panel in the in-app login is blank** on some setups. Workaround is to log in on your real browser and launch games via the registered URI handler (the default flow this installer sets up).

---

## Layout

```
./
├── install.sh          one-shot installer (what you run)
├── flatpak/            legacy flatpak attempt, superseded; .reg files + kernelbase patch script live here
│   ├── src/
│   │   ├── patch-kernelbase.py     LIEF patch adding SetProcessValidCallTargets stub
│   │   ├── win10.reg
│   │   ├── mouse-fix.reg
│   │   ├── webview2-flags.reg
│   │   ├── roblox-uri.reg
│   │   └── dxvk.conf
│   └── io.github.ironpan2.memorylinux.yaml
└── README.md
```

The `flatpak/` directory is kept as an archive — it still carries the useful `.reg` and `patch-kernelbase.py` assets that `install.sh` consumes.

---

## What gets installed where

| Path                                                                          | What                             |
|-------------------------------------------------------------------------------|----------------------------------|
| `~/Games/roblox-memory/`                                                      | prefix, launcher, memory.exe     |
| `~/Games/roblox-memory/pfx/`                                                  | Wine prefix with Roblox          |
| `~/.local/share/Steam/compatibilitytools.d/GE-Proton11-1/`                    | patched Proton                   |
| `~/.local/share/umu/umu-run`                                                  | umu-launcher                     |
| `~/.local/share/memoryLinux/venv/`                                            | python venv w/ LIEF (one-time)   |
| `~/.local/share/applications/roblox-memory.desktop`                           | URI handler for `roblox-player:` |
