---
name: dsh-orphan-folder-cleanup
description: Safely delete confirmed leftover application folders, app data, and regenerable caches on Windows, with allowlist validation, backup-before-delete, per-item logging, non-admin handling, and post-delete verification. Use only after the user has confirmed a concrete path list (for example the output of dsh-app-inventory-audit), or when they say "clean up these leftovers / 按清单清理 / 删除这些残留". Do not use to discover candidates, to uninstall software, or to delete anything the user has not approved.
metadata:
  short-description: Delete confirmed leftover folders safely
---

# Windows Orphan Folder Cleanup

Destructive. The only safe default is: **validate → back up → delete → verify → report**. Do not skip a step because the folders "look obviously junk".

## Preconditions

1. A plan file (JSON) derived from an audit — schema and example in `references/plan-schema.md`.
2. **Explicit user approval of the concrete list.** Quote back item count and total size, and confirm the plan includes anything with user data. If approval is ambiguous, stop and ask.
3. Decide the backup policy: every item whose group is `user-data` or whose folder may hold `*.sqlite`, notes, models, login state **must** be backed up to a different drive before deletion.

## Hard rules (enforced by the scripts; never bypass)

1. **Allowlist only.** Each path must be absolute, under a root from the plan allowlist, and must not match a protected pattern. No wildcards, no drive roots, no relative paths.
2. **Resolve before delete.** `Get-Item -LiteralPath` the exact path; refuse reparse points (junctions/symlinks) so you never delete the link target.
3. **Backup then verify.** Copy, then compare recursive byte count and file count. If they differ, the item is `BLOCKED-BACKUP` and is not deleted.
4. **One item at a time, always logged.** Continue past failures; never abort silently.
5. **Never fake success.** A non-admin failure (`Access is denied`) must be logged as `FAILED` with the reason, then finished with `admin-fixup.ps1`. Do not retry with a different deletion trick and call it done.
6. **Recycle bin via shell.** `Clear-RecycleBin -DriveLetter C -Force`; never delete `C:\$RECYCLE.BIN` content structure directly.
7. **Never delete** `C:\Windows\Installer`, `ProgramData\Package Cache`, MSI-tracked component folders, boot-start driver payloads, licensing/activation directories, or anything not present in the plan.

## Procedure

Run the scripts from this skill's folder (the directory containing this SKILL.md); if your working directory differs, prefix the script path accordingly (`<skill-dir>\scripts\...`).

### 1. Dry run

```powershell
pwsh -NoProfile -File scripts/execute-cleanup.ps1 -PlanJson .\plan.json -DryRun
```

Confirm the resolved paths, sizes, backup flags and admin/denied expectations.

### 2. Execute

```powershell
pwsh -NoProfile -File scripts/execute-cleanup.ps1 -PlanJson .\plan.json `
  -BackupRoot 'D:\C_cleanup_backup_2026-10-25' -EmptyRecycleBin
```

Writes `deletion_log.csv` next to the plan. Output ends with per-group totals, failures, backup results, and C: free-space delta.

### 3. Finish permission failures

```powershell
pwsh -NoProfile -File scripts/admin-fixup.ps1 -PlanJson .\plan.json -LogCsv .\deletion_log.csv
```

Self-elevates through UAC and deletes only the items logged as `FAILED`. If UAC is unavailable, tell the user to run the generated command themselves; the remaining size is usually small.

### 4. Verify

For every deleted path assert `Test-Path` is false. Compare `Get-PSDrive C` free space with the summed sizes; a mismatch of a few hundred MB is normal (metadata, sparse files, recycle bin).

If an item failed halfway (some files gone, some denied), compare its current file count with the pre-run count: unchanged means intact; changed means finish the deletion elevated **or** restore it from the backup — never leave a half-deleted app directory.

### 5. Report

Include: total deleted (count + MB), per-group breakdown, recycle bin, failures with ACL reason, backup location + restore command, and the explicit list of "looks like leftover but was kept". Deliver the log CSV as an artifact.

## Restore

```powershell
pwsh -NoProfile -File scripts/restore-backup.ps1 -BackupRoot 'D:\C_cleanup_backup_2026-10-25' -List
pwsh -NoProfile -File scripts/restore-backup.ps1 -BackupRoot 'D:\C_cleanup_backup_2026-10-25' -Path 'Roaming\CherryStudioDev'
```

## Environment notes

- Non-admin is the common case: `Program Files`, `Program Files (x86)` and `C:\` top-level items fail; `ProgramData` is mixed (vendor ACLs).
- Some `ProgramData` folders deny even when the root is writable (e.g. Chocolatey `.locks`).
- Backups should go to another local drive (D:/E:), never back into `C:\` — that defeats the cleanup and may double space pressure.
- Deleting caches such as `npm-cache`/`pnpm-cache`/`uv`/`electron` is safe: they rebuild on next use; state this in the report so the user is not surprised by re-downloads.
