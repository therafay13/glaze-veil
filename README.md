# glaze-veil

A small companion for **[GlazeWM](https://github.com/glzr-io/glazewm)** + **[Zebar](https://github.com/glzr-io/zebar)** (Attaquer bar) that keeps the transparent top bar and tiling gaps looking clean.

While you have apps open, **glaze-veil** paints your *current* Windows wallpaper as a layer over the desktop so shortcut icons don’t bleed through the bar or gaps. Minimize everything on a monitor and the normal desktop (with icons) comes back.

It also helps the Attaquer top bar show a **real icon for any open app** (not only a hardcoded list).

> Not a fork of GlazeWM or Zebar. This is a config + helper rice that you run *with* those apps.  
> Bar theme lineage: [iAttaquer/.glzr](https://github.com/iAttaquer/.glzr) (Attaquer).

## Features

- Wallpaper **overlay** (same wallpaper you already use — not a second image)
- Overlay **hides** when a monitor has no visible GlazeWM windows
- Tied to GlazeWM lifecycle (starts/stops with the WM)
- Optional **dynamic app icons** for Attaquer
- Suggested laptop-friendly **gaps** for a 26px Attaquer bar
- Does **not** permanently hide desktop icons or rewrite your wallpaper settings

## Prerequisites

1. [GlazeWM](https://github.com/glzr-io/glazewm/releases)
2. [Zebar](https://github.com/glzr-io/zebar/releases)
3. Attaquer widget pack (Zebar marketplace: `iattaquer.attaquer`, or build from [iAttaquer/.glzr](https://github.com/iAttaquer/.glzr))
4. Windows 10/11, PowerShell 5.1+

## Quick install

```powershell
git clone https://github.com/CanuteTheWise/glaze-veil.git
cd glaze-veil
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlazeVeil.ps1
```

The installer:

1. Creates a local Attaquer pack (if missing) and applies the dynamic-icon patch  
2. Writes Zebar `settings.json` to auto-start Attaquer  
3. Prints the exact GlazeWM `startup_commands` / `shutdown_commands` / gap snippets for your clone path  
4. Reminds you to save YAML/JSON as **UTF-8 without BOM**

Then reload GlazeWM (`Alt+Shift+R` or restart GlazeWM).

## Manual stop (if overlay survives a force-kill of GlazeWM)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-DesktopHelper.ps1
```

More detail: [DOCUMENTATION.md](DOCUMENTATION.md)

## Repo layout

| Path | Purpose |
|------|---------|
| `scripts/GlazeDesktopHelper.ps1` | Overlay + icon cache loop |
| `scripts/Start-DesktopHelper.ps1` | Detached launcher (GlazeWM startup) |
| `scripts/Stop-DesktopHelper.ps1` | Clean shutdown |
| `scripts/Install-GlazeVeil.ps1` | One-shot setup helper |
| `scripts/Apply-AttaquerDynamicIcons.ps1` | Patch local Attaquer pack |
| `templates/` | Sample Zebar settings + config snippets |
| `DOCUMENTATION.md` | Full design notes for future maintenance |

## Credits

- [glzr-io/glazewm](https://github.com/glzr-io/glazewm)
- [glzr-io/zebar](https://github.com/glzr-io/zebar)
- [iAttaquer/.glzr](https://github.com/iAttaquer/.glzr) — Attaquer bar
- Icons in the stock Attaquer pack are from Icons8 (see upstream)

## License

MIT — see [LICENSE](LICENSE). Upstream GlazeWM, Zebar, and Attaquer keep their own licenses.
