param(
  [Parameter(Mandatory = $true)][string]$BackupRoot,
  [string[]]$Path,
  [switch]$List,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BackupRoot)) { throw "Backup root not found: $BackupRoot" }

function Get-TreeSize([string]$p) {
  $s = [long]0; $n = 0
  foreach ($f in [System.IO.Directory]::EnumerateFiles($p, '*', [System.IO.SearchOption]::AllDirectories)) {
    try { $fi = New-Object System.IO.FileInfo $f; $s += $fi.Length; $n++ } catch {}
  }
  [pscustomobject]@{ Size = $s; Files = $n }
}

if ($List -or -not $Path) {
  Write-Output "Backup entries under $BackupRoot :"
  $pattern = '^(Users\\[^\\]+\\AppData\\(Local|Roaming|LocalLow|Programs)\\[^\\]+|ProgramData\\[^\\]+|Program Files( \(x86\))?\\[^\\]+)$'
  Get-ChildItem -LiteralPath $BackupRoot -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName.Substring($BackupRoot.Length).TrimStart('\') -match $pattern } |
    ForEach-Object {
      $st = Get-TreeSize $_.FullName
      [pscustomobject]@{
        RestorePath = 'C:\' + $_.FullName.Substring($BackupRoot.Length).TrimStart('\')
        SizeMB      = [math]::Round($st.Size / 1MB, 2)
        Files       = $st.Files
        LastWrite   = $_.LastWriteTime
      }
    } | Sort-Object RestorePath | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
  Write-Output 'Restore one entry with:  restore-backup.ps1 -BackupRoot <root> -Path "<RestorePath or relative path>"'
  return
}

foreach ($p in $Path) {
  $rel = if ($p -match '^[A-Za-z]:\\') { $p.Substring(3) } else { $p.TrimStart('\') }
  $src = Join-Path $BackupRoot $rel
  $dest = if ($p -match '^[A-Za-z]:\\') { $p } else { 'C:\' + $rel }

  if (-not (Test-Path -LiteralPath $src)) { Write-Warning "Not in backup: $src"; continue }
  if ((Test-Path -LiteralPath $dest) -and -not $Force) {
    Write-Warning "Target already exists (use -Force to overwrite): $dest"
    continue
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
  $a = Get-TreeSize $src; $b = Get-TreeSize $dest
  $status = if ($a.Size -eq $b.Size -and $a.Files -eq $b.Files) { 'RESTORED' } else { 'MISMATCH' }
  Write-Output ("{0}: {1} ({2} MB / {3} files)" -f $status, $dest, [math]::Round($b.Size / 1MB, 2), $b.Files)
}
