param(
  [string]$OutDir = '.app-inventory',
  [string[]]$AppDrive = @('D:')
)
$ErrorActionPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Save-Json($obj, [string]$name) {
  $path = Join-Path $OutDir $name
  ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $path -Encoding UTF8
  return @($obj).Count
}

# ---------- 1. uninstall entries (3 hives) ----------
$hives = @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$apps = foreach ($h in $hives) {
  Get-ItemProperty $h | Where-Object { $_.DisplayName } | ForEach-Object {
    [pscustomobject]@{
      DisplayName     = $_.DisplayName
      DisplayVersion  = $_.DisplayVersion
      Publisher       = $_.Publisher
      InstallLocation = $_.InstallLocation
      DisplayIcon     = $_.DisplayIcon
      UninstallString = $_.UninstallString
      RegPath         = ($_.PSPath -replace 'Microsoft\.PowerShell\.Core\\Registry::', '')
    }
  }
}
$apps = $apps | Sort-Object DisplayName -Unique
$nApps = Save-Json $apps 'uninstall.json'

# ---------- 2. AppX / MSIX packages ----------
$appxKeys = @(
  'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages',
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications'
)
$appx = foreach ($k in $appxKeys) {
  Get-ChildItem $k -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName
}
$appx = @($appx | Sort-Object -Unique)
($appx -join "`r`n") | Set-Content -LiteralPath (Join-Path $OutDir 'appx.txt') -Encoding UTF8

# ---------- 3. services (registry, WMI-free) ----------
$services = @()
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' | ForEach-Object {
  $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
  if ($p.ImagePath -or $p.ServiceDll) {
    $services += [pscustomobject]@{
      Name = $_.PSChildName; ImagePath = $p.ImagePath; ServiceDll = $p.ServiceDll
      Start = $p.Start; Type = $p.Type
    }
  }
}
$nSvc = Save-Json $services 'services.json'

# ---------- 4. Run keys ----------
$run = @()
foreach ($k in @(
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
  'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
  'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
  $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
  if ($p) {
    $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } |
      ForEach-Object { $run += [pscustomobject]@{ Key = $k; Name = $_.Name; Value = $_.Value } }
  }
}
$nRun = Save-Json $run 'run.json'

# ---------- 5. App Paths ----------
$appPaths = @()
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths' -ErrorAction SilentlyContinue | ForEach-Object {
  $v = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(default)'
  if ($v) { $appPaths += [pscustomobject]@{ Exe = $_.PSChildName; Path = $v } }
}
$nAp = Save-Json $appPaths 'app_paths.json'

# ---------- 6. shortcuts (resolved targets) ----------
$shell = New-Object -ComObject WScript.Shell
$lnkRoots = @(
  "$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop",
  "$env:ProgramData\Microsoft\Windows\Start Menu",
  "$env:APPDATA\Microsoft\Windows\Start Menu",
  "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch"
)
$shortcuts = @()
foreach ($r in $lnkRoots) {
  Get-ChildItem -LiteralPath $r -Recurse -Filter *.lnk -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $t = ''
    try { $t = $shell.CreateShortcut($_.FullName).TargetPath } catch {}
    $shortcuts += [pscustomobject]@{ Lnk = $_.FullName; Target = $t; MTime = $_.LastWriteTime }
  }
}
$nLnk = Save-Json $shortcuts 'shortcuts.json'

# ---------- 7. UserAssist (last-run, ROT13-encoded) ----------
function Rot13([string]$s) {
  -join ($s.ToCharArray() | ForEach-Object {
    $c = $_; if ($c -match '[a-zA-Z]') {
      $b = [int][char]$c; $off = if ($c -cmatch '[a-z]') { 97 } else { 65 }
      [char]((($b - $off + 13) % 26) + $off)
    } else { $c }
  })
}
$ua = @()
foreach ($g in @('{CEBFF5CD-ACE2-4F4F-9178-9926F41749EA}', '{F4E57C4B-2036-45F0-A9AB-443BCFE33D9F}')) {
  $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\$g\Count"
  $p = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
  if (-not $p) { continue }
  foreach ($v in $p.GetValueNames()) {
    $d = $p.GetValue($v)
    if ($d -isnot [byte[]] -or $d.Length -lt 68) { continue }
    $runs = [BitConverter]::ToInt32($d, 4)
    $ft = [BitConverter]::ToInt64($d, 60)
    $last = $null
    if ($ft -gt 0) { try { $last = [datetime]::FromFileTimeUtc($ft).ToLocalTime() } catch {} }
    $ua += [pscustomobject]@{ GUID = $g; Name = (Rot13 $v); Runs = $runs; LastRun = $last }
  }
}
$ua = $ua | Sort-Object LastRun -Descending
$nUa = Save-Json $ua 'userassist.json'

# ---------- 8. application directories on data drives ----------
$appDirs = @()
foreach ($d in $AppDrive) {
  if (-not (Test-Path -LiteralPath $d)) { continue }
  Get-ChildItem -LiteralPath $d -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('$RECYCLE.BIN', 'System Volume Information', 'Recovery', '$WINDOWS.~TMP') } |
    ForEach-Object {
      $appDirs += [pscustomobject]@{ Level = 1; Name = $_.Name; Path = $_.FullName; MTime = $_.LastWriteTime }
      Get-ChildItem -LiteralPath $_.FullName -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $appDirs += [pscustomobject]@{ Level = 2; Name = $_.Name; Path = $_.FullName; MTime = $_.LastWriteTime } }
    }
}
$nDir = Save-Json $appDirs 'app_dirs.json'

# ---------- 9. running processes ----------
$procs = Get-Process | Where-Object { $_.Path } | Select-Object Name, Path, Id
$nProc = Save-Json $procs 'processes.json'

# ---------- 10. environment summary ----------
$isAdmin = (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$pf = Test-Path 'C:\Windows\Prefetch\*.pf'
$info = [pscustomobject]@{
  CollectedAt   = (Get-Date).ToString('s')
  User          = $env:USERNAME
  ComputerName  = $env:COMPUTERNAME
  IsAdmin       = $isAdmin
  PrefetchTrace = $pf
  Uninstall     = $nApps
  Services      = $nSvc
  RunEntries    = $nRun
  AppPaths      = $nAp
  Shortcuts     = $nLnk
  UserAssist    = $nUa
  AppDirs       = $nDir
  Processes     = $nProc
  AppxPackages  = $appx.Count
}
Save-Json $info 'info.json' | Out-Null

Write-Output ("Evidence written to {0}" -f (Resolve-Path $OutDir))
Write-Output ("uninstall={0} appx={1} services={2} run={3} apppaths={4} shortcuts={5} userassist={6} appdirs={7} processes={8} admin={9}" -f `
  $nApps, $appx.Count, $nSvc, $nRun, $nAp, $nLnk, $nUa, $nDir, $nProc, $isAdmin)
