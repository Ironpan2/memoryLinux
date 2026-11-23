# Roblox (memory, Proton) — Flatpak

Packages the setup we built up during the session:
- GE-Proton 11-1 with `kernelbase.dll` patched to export `SetProcessValidCallTargets`/`Ex` as `return TRUE` (Byfron CFG call bypass).
- WebView2 Evergreen runtime for the in-app login/auth panels.
- DXVK stability config, Windows-10 fingerprint, X11 pointer-grab registry, `roblox://` + `roblox-player://` URI handlers.
- A launcher that prompts for `memory.exe` the first time, runs it once to install its DLL swap into the prefix, and from then on just routes URIs into Proton.

`memory.exe` is **not** bundled — the user picks it from disk on first run.

---

## Build

Three source files in the manifest are tagged `PLACEHOLDER_*_SHA256` because their exact SHAs depend on the download you grab at build time. Before `flatpak-builder` fill them in:

```sh
cd flatpak
# GE-Proton 11-1 release tarball
sha256sum <(curl -sL https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-1/GE-Proton11-1.tar.gz)
# WebView2 evergreen
sha256sum <(curl -sL 'https://go.microsoft.com/fwlink/p/?LinkId=2124703')
# LIEF 1.0.0 cp312 wheel
sha256sum <(curl -sL https://files.pythonhosted.org/packages/py3/l/lief/lief-1.0.0-cp312-cp312-manylinux_2_28_x86_64.whl)
# Zenity 4.0.1
sha256sum <(curl -sL https://download.gnome.org/sources/zenity/4.0/zenity-4.0.1.tar.xz)
```

Drop each digest into the matching `sha256:` field in `io.github.ironpan2.memoryLinux.yaml`, then:

```sh
flatpak-builder --force-clean --install --user build-dir io.github.ironpan2.memoryLinux.yaml
```

The install downloads Proton + WebView2 as `extra-data`, so the install step is fairly large (~700 MB).

## First run

```sh
flatpak run io.github.ironpan2.memoryLinux
```

- Unpacks Proton to `~/.var/app/io.github.ironpan2.memoryLinux/data/GE-Proton`.
- Patches `kernelbase.dll` with `patch-kernelbase.py`.
- Initializes a Wine prefix at `.../prefix/pfx`.
- Installs WebView2 into the prefix.
- Imports Windows-10, mouse-grab, WebView2-flags, and Roblox-URI registry files.
- Pops a Zenity file picker asking for `memory.exe`.
- Runs `memory.exe` once (it installs the fake `RobloxPlayerBeta.dll` + `Mem3API.dll` into the Roblox version folder).
- Drops `dxvk.conf` next to `RobloxPlayerBeta.exe`.
- Registers `roblox-player://` + `roblox://` handlers via an xdg-data `.desktop` so the host browser can launch into the sandbox.

## Play

1. Open your real browser, log in to roblox.com.
2. Click Play on any game.
3. The browser offers *Roblox (memory, Proton)* — accept.
4. Game starts under Proton with the memory overlay.

## Flags

- `flatpak run <id> --install-memory` — re-pick `memory.exe` and rerun the install.
- `flatpak run <id> --reset` — wipe the prefix and config.
- `flatpak run <id> 'roblox-player:1+launchmode:play+gameinfo:...'` — direct launch.

## Known limitation

The memory executor's decrypted-blob hook path has been observed to AV inside its own anonymous memory region on shader-heavy maps (`EXCEPTION_ACCESS_VIOLATION`, same low-16-bit offset across DXVK and WineD3D runs — i.e. it's in the executor, not in Wine / Proton / DXVK). Lower in-game graphics quality or try a newer `memory.exe` build.
