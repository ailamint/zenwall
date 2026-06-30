<#
.SYNOPSIS
    Generate Zenwall mosaic wallpaper(s) from a folder of images.

.DESCRIPTION
    One script for both jobs the old pair did:
      - Set a fresh wallpaper live now           (-SetLive)
      - Render a rotation pack for OS slideshow   (-Count N)
    The collage engine lives in _engine.ps1 (compiled once to WallpaperEngine.dll).

.PARAMETER WallDir
    Source folder of images. Defaults to %USERPROFILE%\Pictures\zenwall-source.

.PARAMETER OutputDir
    Where batch renders go. Defaults to %USERPROFILE%\Pictures\Wallpapers\zenwall.

.PARAMETER Count
    How many wallpapers to render into OutputDir. Default 1.

.PARAMETER SetLive
    After rendering, set the (first) result as the live desktop wallpaper.

.EXAMPLE
    # Set one fresh wallpaper right now (what the old hourly script did):
    .\Generate-Wallpaper.ps1 -WallDir "$HOME\Pictures\arena-scrape\quiet-images" -SetLive

.EXAMPLE
    # Render a 30-image rotation pack for Windows Slideshow (OLED-friendly):
    .\Generate-Wallpaper.ps1 -WallDir "$HOME\Pictures\my-dump" -Count 30
#>
param(
    [string]$WallDir   = "$HOME\Pictures\zenwall-source",
    [string]$OutputDir = "$HOME\Pictures\Wallpapers\zenwall",
    [int]   $Count     = 1,
    [switch]$SetLive
)

# The GDI+/WinForms engine compiles cleanly under Windows PowerShell 5.1
# (full .NET Framework). PowerShell 7+ (Core) splits those types across
# assemblies and the build fails — so transparently relaunch under 5.1.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $winps)) {
        Write-Error "This script needs Windows PowerShell 5.1 (powershell.exe), which wasn't found."
        exit 1
    }
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $argList += "-$k" } }
        else { $argList += "-$k"; $argList += "$v" }
    }
    & $winps @argList
    exit $LASTEXITCODE
}

. "$PSScriptRoot\_engine.ps1"

if (-not (Test-Path $WallDir)) {
    Write-Error "Source folder not found: $WallDir"
    exit 1
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

Write-Host "Source : $WallDir"
Write-Host "Output : $OutputDir"
Write-Host "Count  : $Count"
Write-Host ""

$first = $null
for ($i = 1; $i -le $Count; $i++) {
    $outPath = Join-Path $OutputDir ("zenwall_{0:D3}.png" -f $i)
    Write-Host "  [$i/$Count] $outPath"
    [WallpaperEngine]::CreateZenWallpaper($WallDir, $outPath)
    if (-not $first) { $first = $outPath }
}

if ($SetLive -and $first) {
    Write-Host ""
    Write-Host "Setting live wallpaper: $first"
    [WallpaperEngine]::SetWallpaper($first)
}

Write-Host ""
if ($Count -gt 1) {
    Write-Host "Done. For OLED rotation, point Settings > Personalization > Background > Slideshow at:"
    Write-Host "  $OutputDir"
}
