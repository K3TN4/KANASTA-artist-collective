$ErrorActionPreference = "Stop"

$RepoRoot = "C:\Users\anton\Documents\GitHub\KANASTA-artist-collective"
$ArtistsRoot = Join-Path $RepoRoot "images\works\KANASTA-artists-folders"
$ManifestPath = Join-Path $RepoRoot "images\works\works.json"

$Tiers = @("60%", "30%", "10%")
$Weights = @{
    "60%" = 60
    "30%" = 30
    "10%" = 10
}
$Extensions = @(".jpg", ".jpeg", ".png", ".webp", ".avif", ".gif", ".bmp", ".tif", ".tiff")

function WebPath {
    param([string]$Value)
    return ($Value -replace "\\", "/")
}

function ManifestPathFor {
    param(
        [string]$Artist,
        [string]$Kind,
        [string]$Tier,
        [string]$FileName
    )

    return (WebPath "images\works\KANASTA-artists-folders\$Artist\$Kind\$Tier\$FileName")
}

function Normalize-FileKey {
    param(
        [string]$Name,
        [string]$Artist
    )

    $value = [System.IO.Path]::GetFileName($Name)

    # Usun znane rozszerzenia, takze podwojne: .jpg.jpg
    while ($true) {
        $ext = [System.IO.Path]::GetExtension($value)
        if ([string]::IsNullOrWhiteSpace($ext)) { break }
        if ($Extensions -notcontains $ext.ToLowerInvariant()) { break }
        $value = [System.IO.Path]::GetFileNameWithoutExtension($value)
    }

    $prefix = $Artist + "_"
    if ($value.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring($prefix.Length)
    }

    $value = $value.Trim().ToLowerInvariant()
    $value = $value -replace '[\s_]+', '_'
    return $value
}

function Find-MatchingFile {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$FullName,
        [string]$Artist
    )

    # 1. Najpierw dokladna nazwa, bez zadnego zgadywania.
    $exact = @($Files | Where-Object { $_.Name -ceq $FullName } | Select-Object -First 1)
    if ($exact.Count -gt 0) { return $exact[0] }

    # 2. Potem nazwa bez rozszerzenia / z prefiksem artysty.
    $key = Normalize-FileKey -Name $FullName -Artist $Artist
    $same = @($Files | Where-Object {
        (Normalize-FileKey -Name $_.Name -Artist $Artist) -eq $key
    } | Select-Object -First 1)
    if ($same.Count -gt 0) { return $same[0] }

    return $null
}

function Get-WorkRecord {
    param(
        [string]$Artist,
        [string]$Tier,
        [System.IO.FileInfo]$FullFile,
        [System.IO.FileInfo]$ThumbFile,
        [System.IO.FileInfo]$ViewFile
    )

    $base = [System.IO.Path]::GetFileNameWithoutExtension($FullFile.Name)
    $title = $base
    $technique = ""
    $dimensions = ""
    $year = ""

    # Odczyt podstawowych danych od konca nazwy pliku.
    if ($base -match "^(.*)_(\d{4})$") {
        $beforeYear = $Matches[1]
        $year = $Matches[2]
        if ($beforeYear -match "^(.*)_([^_]+)$") {
            $beforeDimensions = $Matches[1]
            $dimensions = $Matches[2]
            $parts = $beforeDimensions -split "_"
            if ($parts.Count -ge 3) {
                $title = $parts[1]
                $technique = ($parts[2..($parts.Count - 1)] -join "_")
            } elseif ($parts.Count -eq 2) {
                $title = $parts[1]
            } else {
                $title = $beforeDimensions
            }
        }
    }

    return [ordered]@{
        id = "$Artist|$base|$Tier"
        title = $title.Trim()
        artist = $Artist
        technique = $technique.Trim()
        year = $year
        dimensions = $dimensions.Trim()
        tier = $Tier
        weight = $Weights[$Tier]
        thumb = ManifestPathFor $Artist "thumbs" $Tier $ThumbFile.Name
        view = ManifestPathFor $Artist "view" $Tier $ViewFile.Name
        full = ManifestPathFor $Artist "full" $Tier $FullFile.Name
    }
}

if (-not (Test-Path -LiteralPath $ArtistsRoot -PathType Container)) {
    throw "Brak folderu: $ArtistsRoot"
}

$works = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[string]

$artistDirs = @(Get-ChildItem -LiteralPath $ArtistsRoot -Directory | Sort-Object Name)

foreach ($artistDir in $artistDirs) {
    $artist = $artistDir.Name
    foreach ($tier in $Tiers) {
        $thumbDir = Join-Path $artistDir.FullName "thumbs\$tier"
        $viewDir = Join-Path $artistDir.FullName "view\$tier"
        $fullDir = Join-Path $artistDir.FullName "full\$tier"

        if (-not (Test-Path -LiteralPath $fullDir -PathType Container)) {
            $warnings.Add("$artist - brak full\$tier")
            continue
        }
        if (-not (Test-Path -LiteralPath $thumbDir -PathType Container)) {
            $warnings.Add("$artist - brak thumbs\$tier")
            continue
        }
        if (-not (Test-Path -LiteralPath $viewDir -PathType Container)) {
            $warnings.Add("$artist - brak view\$tier")
            continue
        }

        $fullFiles = @(
            Get-ChildItem -LiteralPath $fullDir -File |
            Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name
        )
        $thumbFiles = @(
            Get-ChildItem -LiteralPath $thumbDir -File |
            Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() }
        )
        $viewFiles = @(
            Get-ChildItem -LiteralPath $viewDir -File |
            Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() }
        )

        foreach ($fullFile in $fullFiles) {
            $thumbFile = Find-MatchingFile -Files $thumbFiles -FullName $fullFile.Name -Artist $artist
            $viewFile = Find-MatchingFile -Files $viewFiles -FullName $fullFile.Name -Artist $artist

            if ($null -eq $thumbFile) {
                $warnings.Add("Brak thumbs\$tier dla: $artist\$($fullFile.Name)")
                continue
            }
            if ($null -eq $viewFile) {
                $warnings.Add("Brak view\$tier dla: $artist\$($fullFile.Name)")
                continue
            }

            $works.Add([pscustomobject](Get-WorkRecord `
                -Artist $artist `
                -Tier $tier `
                -FullFile $fullFile `
                -ThumbFile $thumbFile `
                -ViewFile $viewFile))
        }
    }
}

$ordered = @($works | Sort-Object artist, @{Expression={
    switch ($_.tier) {
        "60%" { 0 }
        "30%" { 1 }
        "10%" { 2 }
    }
}}, title)

$json = $ordered | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText(
    $ManifestPath,
    $json,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DONE - works.json created" -ForegroundColor Green
Write-Host "Works found: $($ordered.Count)" -ForegroundColor Green
Write-Host "Manifest: $ManifestPath" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNINGS:" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "- $warning" -ForegroundColor Yellow
    }
} else {
    Write-Host "No warnings. Every work has thumbs, view and full." -ForegroundColor Green
}



