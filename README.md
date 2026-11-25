# memoryLinux

Run Roblox + the **memory** executor on Linux via a patched GE-Proton. Single bash installer — no flatpak, no package managers to wrestle with. Mirrors a known-working setup reached end-to-end: Byfron CFG stub, WebView2 for login, `roblox-player://` URI handler so browser-based play works, DXVK stability tuning, X11 pointer-grab for first-person.

`memory.exe` is **not bundled** — the installer prompts for it and you point at your own copy.

---

## Install

### 1. Prerequisites

| Distro             | Install                                                                     |
|--------------------|-----------------------------------------------------------------------------|
| Ubuntu / Debian    | `sudo apt install git curl bubblewrap python3 python3-venv python3-pip zenity xdg-utils desktop-file-utils cabextract unzip` |
| Fedora             | `sudo dnf install git curl bubblewrap python3 python3-pip zenity xdg-utils desktop-file-utils cabextract unzip`             |
| Arch / Manjaro     | `sudo pacman -S git curl bubblewrap python zenity xdg-utils desktop-file-utils cabextract unzip`                            |
| openSUSE           | `sudo zypper install git curl bubblewrap python3 python3-pip zenity xdg-utils desktop-file-utils cabextract unzip`          |
| Void               | `sudo xbps-install -S git curl bubblewrap python3 python3-pip zenity xdg-utils desktop-file-utils cabextract unzip`         |

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

## Updating Roblox

When Roblox servers reject your client as outdated (`"Please update to the latest Roblox"`), from inside your `memoryLinux/` clone run:

```sh
./install.sh --update
```

What this does:
1. Downloads the newest `RobloxPlayerInstaller.exe` from roblox.com.
2. Runs it inside the sandbox — Roblox installs a new `version-XXXXXXXX/` folder next to the old one.
3. Re-runs your `memory.exe` so the DLL swap lands in the new version folder.
4. Drops `dxvk.conf` next to the new `RobloxPlayerBeta.exe`.

The URI handler (`launch-uri.sh`) auto-picks the newest `version-*` folder by mtime at every launch — no manual pointer updates needed.

## Downgrading Roblox

For when the latest version broke something and you need a specific earlier one — e.g. your `memory.exe` only patches cleanly against `version-2c6fd5e09aaf4cfa`:

```sh
./install.sh --downgrade 2c6fd5e09aaf4cfa
```

What this does:
1. Fetches `setup.rbxcdn.com/version-<hash>-rbxPkgManifest.txt`.
2. Downloads every `.zip` package the manifest lists and extracts each into its correct subdirectory inside a new `version-<hash>/` folder.
3. Writes a minimal `AppSettings.xml` so the client knows its own id.
4. Re-runs `memory.exe` so the DLL swap lands in this folder.

After downgrade, the handler will still auto-pick the newest folder. If you have a newer `version-*` alongside and want to force the downgrade to win, just touch it:

```sh
touch ~/Games/roblox-memory/pfx/drive_c/users/steamuser/AppData/Local/Roblox/Versions/version-2c6fd5e09aaf4cfa
```

Where to find valid version hashes: Roblox version-tracking sites publish them publicly; e.g. [rblx.trade/version](https://rblx.trade/version), [rdd.weao.xyz](https://rdd.weao.xyz/), or the `clientsettings.roblox.com` API. The hash is the hex suffix on `version-XXXXXXXX`.

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

- **"Unknown heap type: #Schema" when running memory.exe** — this means .NET Framework 4.x isn't installed in the prefix yet. The installer now runs `winetricks -q dotnet48` automatically; if you built from an older clone, re-pull and re-run `./install.sh` (it's idempotent).
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
