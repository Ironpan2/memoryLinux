# memoryLinux

Run Roblox + the **memory** executor on Linux via a patched Proton, packaged as a Flatpak.

The flatpak bundles GE-Proton with a one-time binary patch to `kernelbase.dll` (adds a no-op `SetProcessValidCallTargets` stub so Byfron/Hyperion stops aborting under Wine), Microsoft Edge WebView2 for the in-app auth panels, DXVK stability tuning, a Win10 fingerprint, X11 pointer-grab, and `roblox-player://` URI handlers. `memory.exe` is **not** bundled — the flatpak prompts for it on first run and you point it at your own copy.

---

## Install (fresh machine)

### 1. Install `flatpak` + `flatpak-builder` + `git`

| Distro              | Command                                                      |
|---------------------|--------------------------------------------------------------|
| Ubuntu / Debian     | `sudo apt install flatpak flatpak-builder git`               |
| Fedora              | `sudo dnf install flatpak flatpak-builder git`               |
| Arch / Manjaro      | `sudo pacman -S flatpak flatpak-builder git`                 |
| openSUSE            | `sudo zypper install flatpak flatpak-builder git`            |
| Void                | `sudo xbps-install -S flatpak flatpak-builder git`           |

### 2. Add Flathub (once per user)

```sh
flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
```

### 3. Pull the runtime + SDK (one-time, ~1.5 GB)

```sh
flatpak install --user -y flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
```

### 4. Clone this repo

```sh
git clone https://github.com/Ironpan2/memoryLinux
cd memoryLinux/flatpak
```

### 5. Build + install the flatpak (~700 MB extra-data: GE-Proton + WebView2)

```sh
flatpak-builder --force-clean --user --install build-dir io.github.ironpan2.memorylinux.yaml
```

### 6. First launch — installs Roblox + prompts for your `memory.exe`

```sh
flatpak run io.github.ironpan2.memorylinux
```

A file picker opens. Point it at **your own** `memory.exe`. It runs once inside the prefix to install the fake `RobloxPlayerBeta.dll` + `Mem3API.dll` into the Roblox version folder.

### 7. Play

1. Open your normal browser on Linux, go to [roblox.com](https://roblox.com), log in.
2. Click **Play** on any game.
3. Your browser offers *"Roblox (memory, Proton)"* — accept.
4. Game launches under the sandbox with the memory executor overlay active.

Direct launch with a URI (bypass the browser):

```sh
flatpak run io.github.ironpan2.memorylinux 'roblox-player:1+launchmode:play+gameinfo:...'
```

---

## Maintenance

```sh
# re-pick your memory.exe (new build, different file)
flatpak run io.github.ironpan2.memorylinux --install-memory

# wipe prefix + config, start over
flatpak run io.github.ironpan2.memorylinux --reset

# full uninstall
flatpak uninstall --user io.github.ironpan2.memorylinux
rm -rf ~/.var/app/io.github.ironpan2.memorylinux
```

---

## Updating

```sh
cd /path/to/memoryLinux
git pull
cd flatpak
flatpak-builder --force-clean --user --install build-dir io.github.ironpan2.memorylinux.yaml
```

---

## Known issues

- **Heavy games can crash with `EXCEPTION_ACCESS_VIOLATION`.** The fault is inside the executor's own anonymous memory region (same low-16-bit offset across DXVK and WineD3D), not Wine/Proton. Lower in-game graphics quality or try a newer `memory.exe` build.
- **Captcha panel in the in-app login is blank** on some setups. Workaround is to log in on your real browser and launch games via the `roblox-player://` handler (the default flow).

---

## What's inside

```
flatpak/
├── io.github.ironpan2.memorylinux.yaml        flatpak-builder manifest
├── io.github.ironpan2.memorylinux.desktop     scheme handler + launcher
├── io.github.ironpan2.memorylinux.metainfo.xml
├── README.md                                   build/design notes
└── src/
    ├── roblox-memory             entrypoint (--install-memory, --reset, URI dispatch)
    ├── first-run.sh              unpacks Proton, patches kernelbase, installs Roblox + WebView2
    ├── patch-kernelbase.py       LIEF patch adding SetProcessValidCallTargets stub
    ├── pick-memory-exe.sh        zenity/kdialog file picker
    ├── dxvk.conf                 DXVK stability tuning
    ├── win10.reg                 Win10 fingerprint
    ├── mouse-fix.reg             X11 pointer grab (for first-person)
    ├── webview2-flags.reg        WebView2 browser flags
    ├── roblox-uri.reg            in-prefix URI handlers
    └── _true.sh                  noop used to init the prefix
```

See `flatpak/README.md` for build-side technical notes.

Flathub submission: [flathub/flathub#11317](https://github.com/flathub/flathub/pull/11317) — expected to be rejected per Flathub policy, so this repo is the canonical distribution channel.
