---
name: dsh-app-inventory-audit
description: 'Read-only inventory of installed software on a Windows machine and detection of folders/data left behind by software that no longer exists or is unused. Use when the user asks to list installed programs across the C and D drives, compare registry uninstall entries with Program Files/ProgramData/AppData folders, find orphaned or leftover application folders, decide whether a folder still belongs to an installed app, or prepare a cleanup candidate list before any deletion. Trigger phrases include 软件列表, C盘D盘软件, 残留文件夹, 没用的软件, software inventory, leftover folders, orphan app data, what is installed.'
metadata:
  short-description: Audit installed apps and find orphaned folders
---

# Windows App Inventory & Orphan Audit

Read-only. **Never delete, move, or rename anything in this skill.** If the user wants deletion, hand off to `dsh-orphan-folder-cleanup` after they confirm a list.

## Environment realities (verify, don't assume)

- Use PowerShell 7 (`pwsh`). Non-admin sessions are normal; some paths will be unreadable and report 0 files — that is not "empty".
- `Get-CimInstance`/WMI may be blocked by the harness sandbox. Use registry, filesystem, and `.lnk` resolution instead.
- Prefetch is frequently disabled and `Get-Process.Path` only shows live processes. Treat file timestamps and UserAssist as **weak** usage signals, and say so in the report.
- Windows system folders live in `C:\Windows`, `C:\Program Files\Windows*`, `ProgramData\Microsoft*`, `ProgramData\USO*`, `SoftwareDistribution`, `WindowsApps`, `Package Cache`. They are never cleanup candidates — see `references/false-positive-traps.md`.

## Workflow

Run every script below **from this skill's folder** (the directory containing this SKILL.md); if your working directory differs, prefix the script path accordingly (`<skill-dir>\scripts\...`).

### 1. Create a work directory

```powershell
$work = Join-Path $PWD '.app-inventory'
New-Item -ItemType Directory -Force -Path $work | Out-Null
```

### 2. Collect installation + usage evidence (one pass)

```powershell
pwsh -NoProfile -File scripts/collect-evidence.ps1 -OutDir $work -AppDrive D: -AppDrive G:
```

Produces `uninstall.json`, `appx.txt`, `services.json`, `run.json`, `app_paths.json`, `shortcuts.json`, `userassist.json`, `app_dirs.json`, `processes.json`. See `references/evidence-sources.md` for what each file contains and the registry paths behind it.

### 3. Scan candidate roots

Scan each root's immediate children with recursive size/file count/newest-mtime. Typical roots on a Chinese-locale Windows box:

```powershell
$roots = @(
  'C:\Program Files','C:\Program Files (x86)','C:\ProgramData',
  'C:\Users\<user>\AppData\Local','C:\Users\<user>\AppData\Roaming',
  'C:\Users\<user>\AppData\LocalLow','C:\Users\<user>\AppData\Local\Programs',
  'C:\Users\Public'
)
foreach ($r in $roots) {
  pwsh -NoProfile -File scripts/scan-folders.ps1 -Root $r `
    -OutCsv (Join-Path $work ('scan-' + ($r -replace '[^A-Za-z0-9]+','_') + '.csv')) `
    -Exclude Temp
}
```

Skip `C:\` as a whole — it recurses into `Windows` and stalls. Scan only the non-system top-level extras individually (`C:\$GetCurrent`, `C:\AMD`, `C:\LeakHotfix`, `C:\OneDriveTemp`, `C:\.cache`, etc.).

### 4. Cross-match folders against evidence

```powershell
pwsh -NoProfile -File scripts/find-orphans.ps1 -EvidenceDir $work `
  -ScanCsv (Get-ChildItem $work -Filter 'scan-*.csv').FullName `
  -OutCsv (Join-Path $work 'orphans.csv')
```

The matcher returns, per folder: `Verdict` (`LIVE` / `LIKELY_LIVE` / `CHECK` / `ORPHAN`), `PathRefs` (evidence paths rooted inside the folder — strongest signal), `NameInEvidence`, `TokenHits`, size, file count, newest-file date, and `NeedsAdmin`.

### 5. Review every ORPHAN / CHECK ≥ 1 MB by hand

Automation only narrows the list. For each candidate confirm **all** of:

1. No uninstall entry (name, InstallLocation, DisplayIcon, UninstallString) maps to it.
2. No service `ImagePath`, Run key, App Paths entry, or Start-Menu/Desktop shortcut points into it.
3. No same-name app installed on another drive that uses it as its data dir (check `app_dirs.json` and the app's own exe).
4. Not an OS component, boot driver payload, MSI-tracked directory, or licensing directory (see traps reference).

Then classify into: **confirmed orphan**（软件已不存在）/ **probable orphan**（证据强但无法 100% 排除）/ **cache of installed app**（可重建，不是残留）/ **user data, needs consent**（含 sqlite、笔记、模型、登录态）/ **keep**.

### 6. Report

Deliver a table per candidate with: path, size, newest file date, the one piece of evidence that decides it, risk if deleted, and whether it needs admin. Also state totals per class, and explicitly list the "looks like leftover but is live" items that were excluded. Save as Markdown plus a CSV for filtering.

Do not estimate sizes from folder names — always measure. Do not call something unused based only on its install date: apps without autostart are often opened rarely.

## Output contract

`orphans.csv` columns: `Verdict,Name,Path,SizeMB,Files,NewestFile,FolderMTime,LastRun,PathRefs,NameInEvidence,TokenHits,NeedsAdmin`.

`LastRun` comes from UserAssist and is often missing/stale; never present it as authoritative last-use time.

## Hand-off

Only after the user approves the list, switch to `dsh-orphan-folder-cleanup`, passing the confirmed paths and the risk/backup flags from this report.
