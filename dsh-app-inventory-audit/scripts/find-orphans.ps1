param(
  [Parameter(Mandatory = $true)][string]$EvidenceDir,
  [Parameter(Mandatory = $true)][string[]]$ScanCsv,
  [string]$OutCsv = 'orphans.csv',
  [double]$MinSizeMB = 0,
  [switch]$IncludeSystem
)
$ErrorActionPreference = 'SilentlyContinue'

function Load-Json($name) {
  $p = Join-Path $EvidenceDir $name
  if (Test-Path -LiteralPath $p) { return Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
  return @()
}
function Normalize([string]$s) {
  if (-not $s) { return '' }
  ($s -replace '"', '').Trim().TrimEnd('\').ToLowerInvariant()
}

$uninstall = Load-Json 'uninstall.json'
$shortcuts = Load-Json 'shortcuts.json'
$services  = Load-Json 'services.json'
$runs      = Load-Json 'run.json'
$appPaths  = Load-Json 'app_paths.json'
$userAssist= Load-Json 'userassist.json'
$appDirs   = Load-Json 'app_dirs.json'
$procs     = Load-Json 'processes.json'
$appx      = @(Get-Content (Join-Path $EvidenceDir 'appx.txt') -Encoding UTF8 -ErrorAction SilentlyContinue)

# ---- flat evidence blob + structured path list ----
$ev = New-Object System.Collections.Generic.List[string]
$paths = New-Object System.Collections.Generic.List[string]
foreach ($u in $uninstall) {
  foreach ($f in @('DisplayName', 'Publisher', 'InstallLocation', 'DisplayIcon', 'UninstallString')) {
    if ($u.$f) { $ev.Add([string]$u.$f) }
  }
  foreach ($f in @('InstallLocation', 'DisplayIcon')) {
    $n = Normalize ([string]$u.$f); if ($n) { $paths.Add($n) }
  }
}
foreach ($s in $shortcuts) {
  if ($s.Lnk) { $ev.Add([string]$s.Lnk) }
  if ($s.Target) { $ev.Add([string]$s.Target); $paths.Add((Normalize ([string]$s.Target))) }
}
foreach ($s in $services) {
  if ($s.ImagePath) { $ev.Add([string]$s.ImagePath); $paths.Add((Normalize ([string]$s.ImagePath))) }
  if ($s.ServiceDll) { $ev.Add([string]$s.ServiceDll); $paths.Add((Normalize ([string]$s.ServiceDll))) }
  if ($s.Name) { $ev.Add([string]$s.Name) }
}
foreach ($r in $runs) {
  if ($r.Value) { $ev.Add([string]$r.Value); $paths.Add((Normalize ([string]$r.Value))) }
  if ($r.Name) { $ev.Add([string]$r.Name) }
}
foreach ($a in $appPaths) {
  if ($a.Path) { $ev.Add([string]$a.Path); $paths.Add((Normalize ([string]$a.Path))) }
  if ($a.Exe) { $ev.Add([string]$a.Exe) }
}
foreach ($u in $userAssist) { if ($u.Name) { $ev.Add([string]$u.Name); $paths.Add((Normalize ([string]$u.Name))) } }
foreach ($d in $appDirs) { if ($d.Name) { $ev.Add([string]$d.Name) }; if ($d.Path) { $ev.Add([string]$d.Path); $paths.Add((Normalize ([string]$d.Path))) } }
foreach ($p in $procs) { if ($p.Path) { $ev.Add([string]$p.Path); $paths.Add((Normalize ([string]$p.Path))) } }
foreach ($p in $appx) { if ($p) { $ev.Add([string]$p) } }

$evBlob = ($ev -join "`n").ToLowerInvariant()
$evBlobCollapsed = $evBlob -replace '[^\p{L}\p{N}]', ''   # tolerate "Dassault Systemes" vs "DassaultSystemes"
$paths = @($paths | Where-Object { $_ })

$stopwords = @(
  'common','shared','system','microsoft','program','files','data','cache','temp','tmp','logs','log',
  'update','updater','windows','window','local','roaming','app','apps','bin','x86','x64','net',
  'client','service','services','setup','installer','runtime','library','manager','default','user',
  'users','public','documents','desktop','main','core','tool','tools','util','utils','helper','agent'
)

$systemPatterns = @(
  '^[a-z]:\\windows(\\|$)',
  '^[a-z]:\\program files\\windows defender',
  '^[a-z]:\\program files\\windows side',
  '^[a-z]:\\program files\\windowsapps',
  '^[a-z]:\\program files\\modifiablewindowsapps',
  '^[a-z]:\\program files\\common files$',
  '^[a-z]:\\program files \(x86\)\\common files$',
  '^[a-z]:\\programdata\\microsoft',
  '^[a-z]:\\programdata\\uso',
  '^[a-z]:\\programdata\\softwaredistribution',
  '^[a-z]:\\programdata\\package cache',
  '^[a-z]:\\programdata\\packages',
  '^[a-z]:\\programdata\\regid\.',
  '^[a-z]:\\programdata\\ntuser\.pol',
  '^[a-z]:\\\$recycle',
  '^[a-z]:\\system volume information',
  '^[a-z]:\\config\.msi',
  '^[a-z]:\\inetpub',
  '^[a-z]:\\perflogs',
  '^[a-z]:\\recovery',
  '^[a-z]:\\users\\public\\(accountpictures|desktop\.ini|documents|pictures|videos|music|downloads)',
  '^[a-z]:\\users\\[^\\]+\\appdata\\local\\packages',
  '^[a-z]:\\users\\[^\\]+\\appdata\\local\\microsoft',
  '^[a-z]:\\users\\[^\\]+\\appdata\\roaming\\microsoft'
)

$rows = @()
foreach ($csv in $ScanCsv) {
  $rows += Import-Csv -LiteralPath $csv -Encoding UTF8
}

$out = @()
foreach ($r in $rows) {
  $name = [string]$r.Name
  $path = [string]$r.Path
  $pathL = $path.ToLowerInvariant()
  $nameL = $name.ToLowerInvariant()
  $sizeMB = 0.0; [double]::TryParse([string]$r.SizeMB, [ref]$sizeMB) | Out-Null
  if ($sizeMB -lt $MinSizeMB) { continue }

  $isSystem = $false
  foreach ($pat in $systemPatterns) { if ($pathL -match $pat) { $isSystem = $true; break } }

  $refs = @()
  if (-not $isSystem) {
    foreach ($p in $paths) {
      if ($p -eq $pathL -or $p.StartsWith($pathL + '\')) { $refs += $p; if ($refs.Count -ge 3) { break } }
    }
  }

  # tolerate spacing differences ("Dassault Systemes" vs "DassaultSystemes")
  $nameCollapsed = $nameL -replace '[^\p{L}\p{N}]', ''
  $nameInEv = ($nameL.Length -ge 3) -and (
    $evBlob.Contains($nameL) -or
    ($nameCollapsed.Length -ge 4 -and $evBlobCollapsed.Contains($nameCollapsed))
  )

  # split on separators AND camelCase boundaries: OrayClient -> oray, client
  $expanded = $name -creplace '(?<=[a-z])(?=[A-Z])', ' ' -creplace '(?<=[A-Z])(?=[A-Z][a-z])', ' '
  $tokens = @($expanded.ToLowerInvariant() -split '[^\p{L}\p{N}]+' | Where-Object {
    $_.Length -ge 3 -and $_ -notmatch '^[0-9]+$' -and $stopwords -notcontains $_
  } | Select-Object -Unique)
  $tokenHits = @()
  foreach ($t in $tokens) { if ($evBlob.Contains($t) -or $evBlobCollapsed.Contains($t)) { $tokenHits += $t } }

  $verdict =
    if ($isSystem -and -not $IncludeSystem) { 'SYSTEM' }
    elseif ($refs.Count -gt 0) { 'LIVE' }
    elseif ($nameInEv) { 'LIKELY_LIVE' }
    elseif ($tokenHits.Count -gt 0) { 'CHECK' }
    else { 'ORPHAN' }

  $needsAdmin = ($pathL -match '^[a-z]:\\program files') -or ($pathL -match '^[a-z]:\\programdata') -or
                ($pathL -match '^[a-z]:\\\$getcurrent') -or ($pathL -match '^[a-z]:\\[^\\]+$')

  $lastRun = ''
  foreach ($u in $userAssist) {
    if ($u.Name -and ([string]$u.Name).ToLowerInvariant().Contains($pathL) -and $u.LastRun) { $lastRun = $u.LastRun; break }
  }

  $out += [pscustomobject]@{
    Verdict        = $verdict
    Name           = $name
    Path           = $path
    SizeMB         = $sizeMB
    Files          = [int]$r.Files
    NewestFile     = $r.NewestFile
    FolderMTime    = $r.FolderMTime
    LastRun        = $lastRun
    PathRefs       = ($refs -join ' | ')
    NameInEvidence = $nameInEv
    TokenHits      = ($tokenHits -join ',')
    NeedsAdmin     = $needsAdmin
  }
}

$order = @{ 'ORPHAN' = 0; 'CHECK' = 1; 'LIKELY_LIVE' = 2; 'LIVE' = 3; 'SYSTEM' = 4 }
$out = $out | Sort-Object @{ Expression = { $order[$_.Verdict] } }, @{ Expression = { $_.SizeMB }; Descending = $true }
$out | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8

Write-Output ("Rows: {0} -> {1}" -f $out.Count, $OutCsv)
$out | Group-Object Verdict | Select-Object Name, Count | Format-Table -AutoSize | Out-String -Width 80 | Write-Output
Write-Output "Top ORPHAN candidates (review manually; never delete from this script):"
$out | Where-Object { $_.Verdict -eq 'ORPHAN' } | Select-Object -First 15 Name, SizeMB, NewestFile, Path |
  Format-Table -AutoSize | Out-String -Width 180 | Write-Output
