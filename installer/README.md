# Zenwall: Windows auto-rotation installer

The web app makes wallpapers on demand. This folder is for the other half of the
OLED story: a desktop that **rotates on its own**, so nothing ever sits static.

Everything here is plain PowerShell + a tiny compiled C# engine (`_engine.ps1`
builds `WallpaperEngine.dll` on first run). No dependencies, no admin needed.

## Scripts

| Script | What it does |
| --- | --- |
| `Get-ArenaChannel.ps1` | Download a public are.na channel's images into a folder. |
| `Generate-Wallpaper.ps1` | Render mosaic wallpaper(s) from any folder. `-SetLive` to apply now, `-Count N` for a rotation pack. |
| `_engine.ps1` | Shared collage engine (dot-sourced; you don't run this directly). |

## Quick start

```powershell
# 1. (optional) grab a channel, or just point at your own photo folder
.\Get-ArenaChannel.ps1 -Url "quiet-images"

# 2a. set one fresh wallpaper right now
.\Generate-Wallpaper.ps1 -WallDir "$HOME\Pictures\arena-scrape\quiet-images" -SetLive

# 2b. OR render a 30-image rotation pack for the OS slideshow
.\Generate-Wallpaper.ps1 -WallDir "$HOME\Pictures\my-dump" -Count 30
```

For the rotation pack, point **Settings → Personalization → Background →
Slideshow** at the output folder (`%USERPROFILE%\Pictures\Wallpapers\zenwall`)
and set a change interval. That's the OLED-friendly setup: the desktop quietly
reshuffles and no image burns in.

## Hourly regenerate (optional)

If you'd rather generate a *brand-new* layout on a schedule than slideshow a
fixed pack, register a Task Scheduler job:

```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PWD\Generate-Wallpaper.ps1`" -WallDir `"$HOME\Pictures\my-dump`" -SetLive"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
  -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName "Zenwall" -Action $action -Trigger $trigger
```

## Notes

- The engine reads your **primary monitor** resolution and renders to match.
- `WallpaperEngine.dll` is generated locally on first run and is gitignored;
  delete it to force a rebuild after editing `_engine.ps1`.
- Supported inputs: `jpg jpeg png bmp webp gif`.
