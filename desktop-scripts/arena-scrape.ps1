# arena-scrape.ps1
# Usage: .\arena-scrape.ps1 -Url "https://api.are.na/v3/channels/some-slug/contents"
#        .\arena-scrape.ps1 -Url "https://www.are.na/username/channel-name"
# Creates a subfolder under arena-scrape named after the channel slug.

$Url   = Read-Host "Are.na channel URL"
$Limit = 500

$BaseDir   = "$HOME\Pictures\arena-scrape"
$PerPage   = 100
$RateDelay = 300

# Extract slug from either API or web URL
if ($Url -match '/channels/([^/?]+)') {
    $slug = $Matches[1]
} else {
    $slug = ($Url.TrimEnd('/') -split '/')[-1]
}

$OutputDir = Join-Path $BaseDir $slug

if (-not (Test-Path $BaseDir))    { New-Item -ItemType Directory -Path $BaseDir    | Out-Null }
if (-not (Test-Path $OutputDir))  { New-Item -ItemType Directory -Path $OutputDir  | Out-Null }

Write-Host "Channel : $slug"
Write-Host "Output  : $OutputDir"
Write-Host "Limit   : $Limit images"
Write-Host ""

$total   = 0
$skipped = 0
$page    = 1
$done    = $false

while (-not $done) {
    $apiUrl = "https://api.are.na/v3/channels/$slug/contents?per=$PerPage&page=$page"

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
    } catch {
        Write-Warning "Failed to fetch page $page - $($_.Exception.Message)"
        break
    }

    $blocks = $response.data
    if (-not $blocks -or $blocks.Count -eq 0) { break }

    foreach ($block in $blocks) {
        if ($total + $skipped -ge $Limit) { $done = $true; break }
        if (-not $block.image) { continue }

        $src = $block.image.src
        if ($block.image.small.src)  { $src = $block.image.small.src }
        if ($block.image.medium.src) { $src = $block.image.medium.src }
        if ($block.image.large.src)  { $src = $block.image.large.src }
        if (-not $src) { continue }

        $ext = [System.IO.Path]::GetExtension(($src -split '\?')[0])
        if (-not $ext) { $ext = ".jpg" }
        $filename = "arena_$($block.id)$ext"
        $dest = Join-Path $OutputDir $filename

        if (Test-Path $dest) {
            $skipped++
            continue
        }

        try {
            Invoke-WebRequest -Uri $src -OutFile $dest -ErrorAction Stop
            Write-Host "  + $filename"
            $total++
        } catch {
            Write-Warning "Failed $filename - $($_.Exception.Message)"
        }
    }

    if ($blocks.Count -lt $PerPage) { break }
    $page++
    Start-Sleep -Milliseconds $RateDelay
}

Write-Host ""
Write-Host "Done. Downloaded: $total | Already existed: $skipped"
Write-Host "Images in: $OutputDir"

$CollageDir = "$HOME\Pictures\Wallpapers\$slug"
Write-Host ""
Write-Host "Generating collages into $CollageDir ..."
& "$PSScriptRoot\wallpaper-generate-batch.ps1" -WallDir $OutputDir -OutputDir $CollageDir
