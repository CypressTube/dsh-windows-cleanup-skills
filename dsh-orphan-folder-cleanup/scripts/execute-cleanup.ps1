param(
  [Parameter(Mandatory = $true)][string]$PlanJson,
  [string]$BackupRoot,
  [string]$LogPath,
  [string]$Drive = 'C',
  [switch]$DryRun,
  [switch]$SkipBackup,
  [switch]$EmptyRecycleBin
)
$ErrorActionPreference = 'Continue'

# ---------------- load plan ----------------
if (-not (Test-Path -LiteralPath $PlanJson)) { throw "Plan not found: $PlanJson" }
$plan = Get-Content -LiteralPath $PlanJson -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($plan.items)
if ($items.Count -eq 0) { throw "Plan contains no items: $PlanJson" }

$allowlist = @($plan.allowlist | Where-Object { $_ })
if ($allowlist.Count -eq 0) {
  $allowlist = @(
    "$env:APPDATA\",
    "$env:LOCALAPPDATA\",
    'C:\ProgramData\',
    'C:\Program Files\',
    'C:\Program Files (x86)\'
  )
  Write-Warning "Plan has no allowlist; using default roots: $($allowlist -join ' ; ')"
}
if (-not $BackupRoot) { $BackupRoot = [string]$plan.backup_root }
if (-not $LogPath) { $LogPath = Join-Path (Split-Path -Parent $PlanJson) 'deletion_log.csv' }

# protected areas that must never be touched even when allowlisted
$protectedPatterns = @(
  '^[a-z]:\\windows(\\|$)',
  '^[a-z]:\\program files\\windows',
  '^[a-z]:\\program files \(x86\)\\windows',
  '^[a-z]:\\programdata\\microsoft',
  '^[a-z]:\\programdata\\uso',
  '^[a-z]:\\programdata\\softwaredistribution',
  '^[a-z]:\\programdata\\package cache',
  '^[a-z]:\\programdata\\chocolatey$',
  '^[a-z]:\\\$recycle',
  '^[a-z]:\\system volume information',
  '^[a-z]:\\recovery',
  '^[a-z]:\\perflogs'
)

function Test-SafePath([string]$p) {
  if ($p -notmatch '^[a-zA-Z]:\\') { return 'not an absolute drive path' }
  if ($p -match '[*?<>\|]') { return 'wildcards are not allowed' }
  if ($p -match '^[a-zA-Z]:\\?$') { return 'drive root is not deletable' }
  if (($p.Split('\') | Where-Object { $_ }).Count -lt 2) { return 'top-level directory refused' }
  $pL = $p.ToLowerInvariant()
  foreach ($pat in $protectedPatterns) { if ($pL -match $pat) { return "protected path ($pat)" } }
  $ok = $false
  foreach ($root in $allowlist) {
    if ($p.ToLowerInvariant().StartsWith($root.ToLowerInvariant())) { $ok = $true; break }
  }
  if (-not $ok) { return 'outside allowlist' }
  if (Test-Path -LiteralPath $p) {
    $it = Get-Item -LiteralPath $p -Force
    if ($it.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { return 'reparse point refused' }
  }
  return ''
}

function Get-Stat([string]$p) {
  $size = [long]0; $n = 0
  if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]@{ Size = -1; Files = -1 } }
  try {
    foreach ($f in [System.IO.Directory]::EnumerateFiles($p, '*', [System.IO.SearchOption]::AllDirectories)) {
      try { $size += (New-Object System.IO.FileInfo $f).Length; $n++ } catch {}
    }
  } catch {}
  if ($n -eq 0) {
    $it = Get-Item -LiteralPath $p -Force
    if (-not $it.PSIsContainer) { $size = $it.Length; $n = 1 }
  }
  [pscustomobject]@{ Size = $size; Files = $n }
}

$driveLetter = $Drive.TrimEnd(':')
$freeBefore = (Get-PSDrive $driveLetter -ErrorAction SilentlyContinue).Free
$log = @()

foreach ($it in $items) {
  $p = [string]$it.path
  $grp = [string]$it.group
  if (-not $grp) { $grp = 'default' }
  $needBackup = ($it.backup -eq $true) -or ($grp -match 'user-data')

  $bad = Test-SafePath $p
  if ($bad) { $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = 0; Status = 'BLOCKED-UNSAFE'; Detail = $bad }; continue }
  if (-not (Test-Path -LiteralPath $p)) { $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = 0; Status = 'SKIP-MISSING'; Detail = '' }; continue }

  $st = Get-Stat $p
  $sizeMB = [math]::Round($st.Size / 1MB, 2)

  if ($needBackup -and -not $SkipBackup) {
    if (-not $BackupRoot) { $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = $sizeMB; Status = 'BLOCKED-BACKUP'; Detail = 'no backup root configured' }; continue }
    $rel = $p.Substring(3)
    $dest = Join-Path $BackupRoot $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue }
    Copy-Item -LiteralPath $p -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
    $bs = Get-Stat $dest
    if ($bs.Size -ne $st.Size -or $bs.Files -ne $st.Files) {
      $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = $sizeMB; Status = 'BLOCKED-BACKUP'; Detail = "backup mismatch src=$($st.Size)B/$($st.Files)f dst=$($bs.Size)B/$($bs.Files)f" }
      continue
    }
  }

  if ($DryRun) {
    $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = $sizeMB; Status = 'DRYRUN'; Detail = $(if ($needBackup) { 'would back up then delete' } else { 'would delete' }) }
    continue
  }

  try {
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
    $gone = -not (Test-Path -LiteralPath $p)
    $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = $sizeMB; Status = $(if ($gone) { 'DELETED' } else { 'FAILED-STILL-EXISTS' }); Detail = $(if ($gone) { '' } else { 'path still present' }) }
  } catch {
    $msg = $_.Exception.Message; if ($msg.Length -gt 180) { $msg = $msg.Substring(0, 180) }
    $log += [pscustomobject]@{ Group = $grp; Path = $p; SizeMB = $sizeMB; Status = 'FAILED'; Detail = $msg }
  }
}

# ---------------- recycle bin ----------------
$rb = 'skipped'
if ($EmptyRecycleBin -and -not $DryRun) {
  $drive = if ($plan.recycle_drive) { [string]$plan.recycle_drive } else { 'C' }
  $drive = $drive.TrimEnd(':')
  try { Clear-RecycleBin -DriveLetter $drive -Force -ErrorAction Stop; $rb = "cleared ($drive)" }
  catch { $rb = "FAILED: $($_.Exception.Message.Split([char]10)[0])" }
}

$log | Export-Csv -LiteralPath $LogPath -NoTypeInformation -Encoding UTF8
$freeAfter = (Get-PSDrive $driveLetter -ErrorAction SilentlyContinue).Free

Write-Output "================ CLEANUP SUMMARY ================"
$log | Group-Object Group | ForEach-Object {
  $del = @($_.Group | Where-Object { $_.Status -in @('DELETED', 'DRYRUN') })
  $bad = @($_.Group | Where-Object { $_.Status -notin @('DELETED', 'DRYRUN', 'SKIP-MISSING') })
  "{0}: {1} ok / {2:N2} MB; problems {3}" -f $_.Name, $del.Count, (($del | Measure-Object SizeMB -Sum).Sum), $bad.Count
}
Write-Output ("RecycleBin: {0}" -f $rb)
Write-Output ("Free space: {0:N2} GB -> {1:N2} GB (delta {2:N2} GB)" -f ($freeBefore/1GB), ($freeAfter/1GB), (($freeAfter-$freeBefore)/1GB))
Write-Output "Problems:"
$log | Where-Object { $_.Status -notin @('DELETED', 'DRYRUN', 'SKIP-MISSING') } | Format-Table -AutoSize | Out-String -Width 240 | Write-Output
Write-Output ("Log: {0}" -f $LogPath)
