param(
  [Parameter(Mandatory = $true)][string]$Root,
  [Parameter(Mandatory = $true)][string]$OutCsv,
  [string[]]$Exclude = @(),
  [switch]$IncludeRootFiles
)
$ErrorActionPreference = 'SilentlyContinue'

function Get-DirStat([string]$path) {
  $size = [long]0; $count = 0; $max = [datetime]'1900-01-01'
  try {
    foreach ($f in [System.IO.Directory]::EnumerateFiles($path, '*', [System.IO.SearchOption]::AllDirectories)) {
      try {
        $fi = New-Object System.IO.FileInfo $f
        $size += $fi.Length; $count++
        if ($fi.LastWriteTime -gt $max) { $max = $fi.LastWriteTime }
      } catch {}
    }
  } catch {}
  [pscustomobject]@{ SizeBytes = $size; Files = $count; NewestFile = $max }
}

$rows = New-Object System.Collections.ArrayList
foreach ($d in [System.IO.Directory]::EnumerateDirectories($Root)) {
  $di = New-Object System.IO.DirectoryInfo $d
  if ($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }   # skip junctions/symlinks
  if ($Exclude -contains $di.Name) { continue }
  $st = Get-DirStat $d
  [void]$rows.Add([pscustomobject]@{
    Root = $Root; Name = $di.Name; Path = $d
    SizeMB = [math]::Round($st.SizeBytes / 1MB, 1); Files = $st.Files
    NewestFile = $st.NewestFile; FolderMTime = $di.LastWriteTime
  })
}

if ($IncludeRootFiles) {
  foreach ($f in [System.IO.Directory]::EnumerateFiles($Root)) {
    $fi = New-Object System.IO.FileInfo $f
    [void]$rows.Add([pscustomobject]@{
      Root = $Root; Name = $fi.Name; Path = $f
      SizeMB = [math]::Round($fi.Length / 1MB, 2); Files = 1
      NewestFile = $fi.LastWriteTime; FolderMTime = $fi.LastWriteTime
    })
  }
}

$rows | Sort-Object Name | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
Write-Output ("{0}: {1} rows -> {2}" -f $Root, $rows.Count, $OutCsv)
