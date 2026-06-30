<#
.SYNOPSIS
    Download the images from a public are.na channel into a local folder.

.DESCRIPTION
    Fetches every image block from an are.na channel (paginated) and saves the
    largest available variant. Use the resulting folder as the -WallDir for
    Generate-Wallpaper.ps1. Already-downloaded images are skipped, so re-running
    only pulls what's new.

.PARAMETER Url
    are.na channel URL or slug, e.g. "https://www.are.na/user/quiet-images"
    or just "quiet-images".

.PARAMETER OutDir
    Base folder for downloads. A subfolder named after the channel slug is
    created inside it. Defaults to %USERPROFILE%\Pictures\arena-scrape.

.PARAMETER Limit
    Maximum images to download. Default 500.

.EXAMPLE
    .\Get-ArenaChannel.ps1 -Url "quiet-images"
    .\Generate-Wallpaper.ps1 -WallDir "$HOME\Pictures\arena-scrape\quiet-images" -SetLive
#>
param(
    [string]$Url,
    [string]$OutDir = "$HOME\Pictures\arena-scrape",
    [int]   $Limit  = 500
)

if (-not $Url) { $Url = Read-Host "are.na channel URL or slug" }

$PerPage   = 100
$RateDelay = 300

if ($Url -match '/channels/([^/?]+)') { $slug = $Matches[1] }
elseif ($Url -match 'are\.na/[^/]+/([^/?]+)') { $slug = $Matches[1] }
else { $slug = ($Url.TrimEnd('/') -split '/')[-1] }

$OutputDir = Join-Path $OutDir $slug
if (-not (Test-Path $OutDir))    { New-Item -ItemType Directory -Path $OutDir    | Out-Null }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

Write-Host "Channel : $slug"
Write-Host "Output  : $OutputDir"
Write-Host "Limit   : $Limit images"
Write-Host ""

$total = 0; $skipped = 0; $page = 1; $done = $false

while (-not $done) {
    $apiUrl = "https://api.are.na/v3/channels/$slug/contents?per=$PerPage&page=$page"
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    } catch {
        Write-Warning "Failed to fetch page $page - $($_.Exception.Message)"
        break
    }

    $blocks = $response.contents
    if (-not $blocks) { $blocks = $response.data }
    if (-not $blocks -or $blocks.Count -eq 0) { break }

    foreach ($block in $blocks) {
        if ($total + $skipped -ge $Limit) { $done = $true; break }
        if (-not $block.image) { continue }

        $src = $block.image.src
        if ($block.image.medium.src) { $src = $block.image.medium.src }
        if ($block.image.large.src)  { $src = $block.image.large.src }
        if (-not $src) { continue }

        $ext = [System.IO.Path]::GetExtension(($src -split '\?')[0])
        if (-not $ext) { $ext = ".jpg" }
        $dest = Join-Path $OutputDir "arena_$($block.id)$ext"

        if (Test-Path $dest) { $skipped++; continue }

        try {
            Invoke-WebRequest -Uri $src -OutFile $dest -ErrorAction Stop
            Write-Host "  + $(Split-Path $dest -Leaf)"
            $total++
        } catch {
            Write-Warning "Failed $($block.id) - $($_.Exception.Message)"
        }
    }

    if ($blocks.Count -lt $PerPage) { break }
    $page++
    Start-Sleep -Milliseconds $RateDelay
}

Write-Host ""
Write-Host "Done. Downloaded: $total | Already existed: $skipped"
Write-Host "Images in: $OutputDir"
Write-Host ""
Write-Host "Next:  .\Generate-Wallpaper.ps1 -WallDir `"$OutputDir`" -SetLive"
