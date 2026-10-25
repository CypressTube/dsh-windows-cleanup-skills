param(
  [Parameter(Mandatory = $true)][string]$PlanJson,
  [string]$LogCsv,
  [string[]]$Path,
  [switch]$Elevated
)
$ErrorActionPreference = 'Continue'

# ---------------- load plan / targets ----------------
if (-not (Test-Path -LiteralPath $PlanJson)) { throw "Plan not found: $PlanJson" }
$plan = Get-Content -LiteralPath $PlanJson -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($plan.items)

$allowlist = @($plan.allowlist | Where-Object { $_ })
if ($allowlist.Count -eq 0) {
  $allowlist = @("$env:APPDATA\", "$env:LOCALAPPDATA\", 'C:\ProgramData\', 'C:\Program Files\', 'C:\Program Files (x86)\')
}

$protectedPatterns = @(
  '^[a-z]:\\windows(\\|$)', '^[a-z]:\\program files\\windows', '^[a-z]:\\program files \(x86\)\\windows',
  '^[a-z]:\\programdata\\microsoft', '^[a-z]:\\programdata\\uso', '^[a-z]:\\programdata\\softwaredistribution',
  '^[a-z]:\\programdata\\package cache', '^[a-z]:\\programdata\\chocolatey$',
  '^[a-z]:\\\$recycle', '^[a-z]:\\system volume information', '^[a-z]:\\recovery', '^[a-z]:\\perflogs'
)

# targets: explicit -Path, else paths marked FAILED in the log, else every plan item that still exists
$targets = @()
if ($Path) {
  $targets = @($Path)
} elseif ($LogCsv -and (Test-Path -LiteralPath $LogCsv)) {
  $logRows = Import-Csv -LiteralPath $LogCsv -Encoding UTF8
  $targets = @($logRows | Where-Object { $_.Status -like 'FAILED*' -or $_.Status -eq 'BLOCKED-UNSAFE' } | Select-Object -ExpandProperty Path)
} else {
  $targets = @($items | Where-Object { Test-Path -LiteralPath $_.path } | Select-Object -ExpandProperty path)
}
$targets = @($targets | Where-Object { $_ } | Select-Object -Unique)
if ($targets.Count -eq 0) { Write-Output 'Nothing to do.'; return }

# ---------------- self-elevate ----------------
$isAdmin = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Elevated) {
  Write-Host '需要管理员权限，正在请求提升（UAC 请点“是”）...'
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-PlanJson', "`"$PlanJson`"", '-Elevated')
  if ($LogCsv) { $argList += @('-LogCsv', "`"$LogCsv`"") }
  try { Start-Process powershell -Verb RunAs -ArgumentList $argList -ErrorAction Stop; exit 0 }
  catch { Write-Host "提权取消或失败：$($_.Exception.Message)"; if ($Host.Name -eq 'ConsoleHost') { Read-Host '按回车退出' }; exit 1 }
}

function Test-SafePath([string]$p) {
  if ($p -notmatch '^[a-zA-Z]:\\') { return 'not an absolute drive path' }
  if ($p -match '[*?<>\|]') { return 'wildcards are not allowed' }
  if ($p -match '^[a-zA-Z]:\\?$') { return 'drive root is not deletable' }
  if (($p.Split('\') | Where-Object { $_ }).Count -lt 2) { return 'top-level directory refused' }
  $pL = $p.ToLowerInvariant()
  foreach ($pat in $protectedPatterns) { if ($pL -match $pat) { return "protected path ($pat)" } }
  foreach ($root in $allowlist) {
    if ($pL.StartsWith($root.ToLowerInvariant())) { return '' }
  }
  return 'outside allowlist'
}

$outLog = Join-Path (Split-Path -Parent $PlanJson) 'deletion_log_admin.csv'
$log = @()
foreach ($p in $targets) {
  $bad = Test-SafePath $p
  if ($bad) { $log += [pscustomobject]@{ Path = $p; SizeMB = 0; Status = 'BLOCKED-UNSAFE'; Detail = $bad }; continue }
  if (-not (Test-Path -LiteralPath $p)) { $log += [pscustomobject]@{ Path = $p; SizeMB = 0; Status = 'SKIP-MISSING'; Detail = '' }; continue }
  $s = 0; $n = 0
  [System.IO.Directory]::EnumerateFiles($p, '*', [System.IO.SearchOption]::AllDirectories) | ForEach-Object { try { $f = New-Object System.IO.FileInfo $_; $s += $f.Length; $n++ } catch {} }
  try {
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
    $log += [pscustomobject]@{ Path = $p; SizeMB = [math]::Round($s / 1MB, 2); Status = $(if (Test-Path -LiteralPath $p) { 'FAILED-STILL-EXISTS' } else { 'DELETED' }); Detail = '' }
  } catch {
    $msg = $_.Exception.Message; if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) }
    $log += [pscustomobject]@{ Path = $p; SizeMB = [math]::Round($s / 1MB, 2); Status = 'FAILED'; Detail = $msg }
  }
}

$log | Export-Csv -LiteralPath $outLog -NoTypeInformation -Encoding UTF8
Write-Output '==== ADMIN CLEANUP RESULT ===='
$log | Format-Table -AutoSize | Out-String -Width 220 | Write-Output
$ok = @($log | Where-Object { $_.Status -eq 'DELETED' })
Write-Output ("Deleted {0} items / {1:N2} MB; failed {2}" -f $ok.Count, (($ok | Measure-Object SizeMB -Sum).Sum), @($log | Where-Object { $_.Status -notin @('DELETED', 'SKIP-MISSING') }).Count)
Write-Output ("C: free = {0:N2} GB" -f ((Get-PSDrive C).Free / 1GB))
Write-Output ("Log: {0}" -f $outLog)
if ($Host.Name -eq 'ConsoleHost' -and $Elevated) { Read-Host '按回车退出' }
