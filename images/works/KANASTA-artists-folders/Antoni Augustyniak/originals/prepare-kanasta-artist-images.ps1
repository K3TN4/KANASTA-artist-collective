$ErrorActionPreference = 'Stop'

$artistRoot = 'C:\Users\anton\Documents\GitHub\KANASTA-artist-collective\images\works\KANASTA-artists-folders\Antoni Augustyniak'
$thumbMax = 500
$viewMax  = 1800
$fullMax  = 4200

if (-not (Test-Path -LiteralPath $artistRoot)) {
  throw "Nie znaleziono folderu: $artistRoot"
}

Add-Type -AssemblyName System.Drawing

$source = Join-Path $artistRoot 'originals'
if (-not (Test-Path -LiteralPath $source)) {
  New-Item -ItemType Directory -Path $source | Out-Null
  Get-ChildItem -LiteralPath $artistRoot -File -Include *.png,*.jpg,*.jpeg,*.webp | Move-Item -Destination $source
}

$thumbs = Join-Path $artistRoot 'thumbs'
$views  = Join-Path $artistRoot 'view'
$fulls  = Join-Path $artistRoot 'full'
$thumbs,$views,$fulls | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

function Save-ResizedPng($inputPath, $outputPath, $maxSide) {
  $src = [System.Drawing.Image]::FromFile($inputPath)
  try {
    $scale = [Math]::Min(1.0, $maxSide / [Math]::Max($src.Width,$src.Height))
    $w = [Math]::Max(1, [int][Math]::Round($src.Width * $scale))
    $h = [Math]::Max(1, [int][Math]::Round($src.Height * $scale))
    $bmp = New-Object System.Drawing.Bitmap($w,$h,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      try {
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($src,0,0,$w,$h)
      } finally { $g.Dispose() }
      $bmp.Save($outputPath,[System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $bmp.Dispose() }
  } finally { $src.Dispose() }
}

$files = Get-ChildItem -LiteralPath $source -File | Where-Object { $_.Extension -match '^\.(png|jpg|jpeg)$' }
if ($files.Count -eq 0) { throw "Folder originals jest pusty. Włóż tam PNG/JPG i uruchom skrypt ponownie." }

$i=0
foreach ($file in $files) {
  $i++
  $stem = $file.BaseName
  Save-ResizedPng $file.FullName (Join-Path $thumbs ($stem + '.png')) $thumbMax
  Save-ResizedPng $file.FullName (Join-Path $views  ($stem + '.png')) $viewMax
  Save-ResizedPng $file.FullName (Join-Path $fulls  ($stem + '.png')) $fullMax
  Write-Host ("{0}/{1}  {2}" -f $i,$files.Count,$file.Name)
}

Write-Host "Gotowe. Utworzono:"
Write-Host ("thumbs: {0}" -f (Get-ChildItem $thumbs -File).Count)
Write-Host ("view:   {0}" -f (Get-ChildItem $views -File).Count)
Write-Host ("full:   {0}" -f (Get-ChildItem $fulls -File).Count)
Write-Host "Źródła pozostają w folderze originals."
