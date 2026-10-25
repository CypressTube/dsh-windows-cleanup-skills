param(
  [string]$Repo = 'MrCypressBai/dsh-windows-cleanup-skills',
  [string]$Ref = 'main',
  [string]$TargetDir = (Join-Path $env:USERPROFILE '.dsh\skills'),
  [switch]$NoBackup,
  [switch]$SkipVerify
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP ("dsh-skills-$stamp")
$zip = Join-Path $env:TEMP ("dsh-skills-$stamp.zip")
$null = New-Item -ItemType Directory -Force -Path $work

try {
  Write-Host "==> Downloading $Repo@$Ref ..." -ForegroundColor Cyan
  $urls = @(
    "https://codeload.github.com/$Repo/zip/refs/heads/$Ref",
    "https://github.com/$Repo/archive/refs/heads/$Ref.zip"
  )
  $ok = $false
  foreach ($u in $urls) {
    try { Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -TimeoutSec 120; $ok = $true; break }
    catch { Write-Warning "download failed: $u -> $($_.Exception.Message)" }
  }
  if (-not $ok) { throw 'Unable to download repository archive.' }

  Write-Host '==> Extracting ...' -ForegroundColor Cyan
  Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
  $root = Get-ChildItem -LiteralPath $work -Directory | Select-Object -First 1
  if (-not $root) { throw 'Archive layout unexpected: no top-level folder.' }

  $skills = @(Get-ChildItem -LiteralPath $root.FullName -Directory -Filter 'dsh-*')
  if ($skills.Count -eq 0) { throw "No dsh-* skill folders found in $($root.FullName)" }

  $null = New-Item -ItemType Directory -Force -Path $TargetDir
  $results = @()
  foreach ($s in $skills) {
    $skillMd = Join-Path $s.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillMd)) {
      $results += [pscustomobject]@{ Skill = $s.Name; Status = 'SKIP: no SKILL.md' }
      continue
    }
    $head = Get-Content -LiteralPath $skillMd -TotalCount 25 -Encoding UTF8
    $nameLine = @($head | Where-Object { $_ -match '^name:\s*' } | Select-Object -First 1)
    $declared = if ($nameLine.Count -gt 0) { ($nameLine[0] -replace '^name:\s*', '').Trim().Trim("'", '"') } else { '' }
    if (-not $SkipVerify -and $declared -ne $s.Name) {
      $results += [pscustomobject]@{ Skill = $s.Name; Status = "SKIP: name mismatch (declared '$declared')" }
      continue
    }

    $dest = Join-Path $TargetDir $s.Name
    $note = ''
    if (Test-Path -LiteralPath $dest) {
      if ($NoBackup) { Remove-Item -LiteralPath $dest -Recurse -Force }
      else {
        $bak = "$dest.bak-$stamp"
        Move-Item -LiteralPath $dest -Destination $bak -Force
        $note = "backup: $(Split-Path -Leaf $bak)"
      }
    }
    Copy-Item -LiteralPath $s.FullName -Destination $dest -Recurse -Force
    $results += [pscustomobject]@{ Skill = $s.Name; Status = 'INSTALLED'; Note = $note }
  }
}
finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "==> Installed into $TargetDir" -ForegroundColor Green
$results | Format-Table -AutoSize | Out-String -Width 160 | Write-Host

$bad = @($results | Where-Object { $_.Status -ne 'INSTALLED' })
if ($bad.Count -gt 0) { Write-Warning "$($bad.Count) skill(s) were not installed."; exit 1 }

Write-Host 'Restart the DSH session (or wait for the skill watcher) to load the new skills.' -ForegroundColor Yellow
Write-Host '可用技能 / Try: $dsh-app-inventory-audit , $dsh-orphan-folder-cleanup'
