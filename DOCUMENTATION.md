# glaze-veil — Documentation

Maintenance notes for the GlazeWM + Zebar (Attaquer) companion that adds a wallpaper overlay and dynamic app icons.

Upstream apps: [GlazeWM](https://github.com/glzr-io/glazewm), [Zebar](https://github.com/glzr-io/zebar).  
Bar theme lineage: [iAttaquer/.glzr](https://github.com/iAttaquer/.glzr).

---

## Goals

1. Keep Attaquer’s **transparent** top bar.
2. Stop desktop **shortcut icons** bleeding through the bar and GlazeWM gaps — without swapping wallpaper.
3. While apps are visible: show the **same current wallpaper** as an overlay covering desktop icons.
4. When apps on a monitor are all minimized / none open: **hide** that overlay so the normal desktop returns.
5. Optional laptop-friendly **gaps** for a ~26px Attaquer bar.
6. Make **Attaquer** the default Zebar top bar on startup.
7. Show a **real icon for any open app** on the bar (not only a hardcoded map).

---

## Architecture

```
GlazeWM (boss)
├── startup_commands
│   ├── zebar.exe
│   └── Start-DesktopHelper.ps1  →  GlazeDesktopHelper.ps1
├── config_reload_commands
│   └── Start-DesktopHelper.ps1  (single-instance mutex)
└── shutdown_commands
    ├── Stop-DesktopHelper.ps1
    └── taskkill zebar.exe

Zebar
└── settings.json → pack "attaquer" / widget "top-bar"
    └── Local pack: %USERPROFILE%\.glzr\zebar\attaquer\
        └── icons from dist\assets\icons\dynamic\

GlazeDesktopHelper.ps1
├── Overlay windows (title: GlzrWallpaperOverlay)
└── Icon extractor → dynamic PNGs for Attaquer
```

**Lifecycle:** Tied to GlazeWM. When GlazeWM is not running, Windows is normal.

---

## Live paths on a Windows install

| Component | Path |
|-----------|------|
| This repo (clone) | wherever you cloned `glaze-veil` |
| GlazeWM config | `%USERPROFILE%\.glzr\glazewm\config.yaml` |
| Zebar settings | `%USERPROFILE%\.glzr\zebar\settings.json` |
| Local Attaquer pack | `%USERPROFILE%\.glzr\zebar\attaquer\` |
| Marketplace Attaquer | `%APPDATA%\zebar\downloads\iattaquer.attaquer@1.0.1\` |
| GlazeWM CLI | `C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe` |
| Helper log | `<repo>\logs\desktop-helper.log` |

---

## Components

### Desktop helper (`scripts/GlazeDesktopHelper.ps1`)

- Reads wallpaper path from `HKCU\Control Panel\Desktop\WallPaper` (**read-only**).
- One borderless WinForms window per monitor, title `GlzrWallpaperOverlay`, z-order bottom.
- Polls ~750ms: `glazewm.exe query workspaces`.
- Shows overlay when a displayed workspace has non-minimized visible windows; hides otherwise.
- Mutex: `Global\GlazeVM_Zebar_DesktopHelper`.
- Extracts process icons into the local Attaquer `dynamic` folder.

Does **not** permanently set `HideIcons` or rewrite the wallpaper.

### Dynamic icons (`Apply-AttaquerDynamicIcons.ps1`)

Patches Attaquer’s bundle so each app icon prefers:

`./assets/icons/dynamic/{SanitizedProcessName}.png`

Fallback: original hardcoded map → generic icon.

Sanitizer (keep JS + PowerShell in sync):

- Replace `[<>:"/\|?*` + controls] with `_`
- Replace whitespace with `_`

### Suggested gaps

| Setting | Suggested |
|---------|-----------|
| `inner_gap` | `10px` |
| `outer_gap.top` | `36px` |
| other outer | `10px` |

### Encoding

Always save `config.yaml` and `settings.json` as **UTF-8 without BOM**.

- BOM on YAML → GlazeWM: `deserializing from YAML containing more than one document is not supported`
- BOM on JSON → Zebar: `Failed to parse JSON` / `expected value at line 1 column 1`

---

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlazeVeil.ps1
```

Merge the printed snippets into GlazeWM config, reload, restart Zebar.

---

## Verify

```powershell
& "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe" query workspaces

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object { $_.CommandLine -like '*GlazeDesktopHelper.ps1*' }

Get-ChildItem "$env:USERPROFILE\.glzr\zebar\attaquer\dist\assets\icons\dynamic"
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Icons bleed through | Helper not running; check log; confirm ignore rule for `GlzrWallpaperOverlay` |
| Overlay after GlazeWM quit | Force-kill skipped shutdown — use emergency stop below |
| YAML reload fails | Strip UTF-8 BOM from `config.yaml` |
| Zebar JSON error | Strip UTF-8 BOM from `settings.json` |
| Missing app icon | Delete bad PNG in `dynamic\`; confirm `processName` via `glazewm query windows` |

---

## Emergency stop — helper did not exit with GlazeWM

If GlazeWM was force-killed and the overlay / helper remains:

### Method A — stop script (preferred)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-DesktopHelper.ps1
```

### Method B — one-liner

```powershell
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -like '*GlazeDesktopHelper.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

### Method C — Task Manager

End the PowerShell process whose command line contains `GlazeDesktopHelper.ps1`.

Overlay windows titled `GlzrWallpaperOverlay` should then disappear.
