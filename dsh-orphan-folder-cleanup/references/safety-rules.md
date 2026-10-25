# Safety rules for destructive cleanup

Deletion is irreversible. These rules are cheaper than a restore.

## 1. Scope control

- The plan is the single source of truth. Delete **only** paths listed in `items[].path`.
- Every path must be absolute, contain no `*?<>|`, not be a drive root, and live under an `allowlist` prefix.
- Refuse reparse points: `Get-Item` and check `Attributes -band ReparsePoint`. Deleting a junction can wipe the target.
- Refuse top-level single-segment directories (`C:\SomeFolder` at root) — they are almost never app leftovers and the blast radius is large.
- Protected patterns the scripts always reject, even if allowlisted:
  `C:\Windows`, `Program Files\Windows*`, `ProgramData\Microsoft`, `ProgramData\USO*`,
  `SoftwareDistribution`, `Package Cache`, `ProgramData\chocolatey` itself, `$RECYCLE.BIN`,
  `System Volume Information`, `Recovery`, `PerfLogs`.

## 2. Backup policy

Back up to **another local drive** (D:/E:/G:), never back into `C:`.

Back up when the path is group `user-data`, or when a quick look finds any of:

- `*.sqlite`, `*.db` with user tables, `Notes/`, `Agents/`, `Sessions/`, `*.md` drafts
- model/CAE autosave or journal files, `Autosave/`
- `Login Data`, `Cookies`, `Local Storage`, `Network/` (a Chromium profile may hold a signed-in session)
- license/activation files (`*.lic`, `ProgramData\Reprise`, `SafeNet Sentinel`, `FLEXnet`)

Verification is mandatory: copy, then compare recursive **byte count and file count**. On mismatch the item becomes `BLOCKED-BACKUP` and is not deleted. A silent partial copy is worse than no backup.

Name the backup root with a date: `D:\C_cleanup_backup_2026-10-25`. Tell the user it can be deleted once satisfied.

## 3. Execution discipline

- One item at a time; keep going after failures.
- Log every item: `Group, Path, SizeMB, Status, Detail`.
- Status vocabulary: `DELETED`, `SKIP-MISSING`, `DRYRUN`, `FAILED`, `FAILED-STILL-EXISTS`, `BLOCKED-UNSAFE`, `BLOCKED-BACKUP`.
- Always dry-run first (`-DryRun`) and read the resolved list before the real pass.
- Never substitute `cmd /c rd /s /q` to "get past" an access-denied error; the denial is information.

## 4. Non-admin reality

Typical results from an unelevated shell:

- `Program Files`, `Program Files (x86)`, `C:\` top-level: `Access is denied` — expected.
- `ProgramData`: mixed. Vendor ACLs deny some subfolders even when the root is writable (e.g. Chocolatey `.locks`).
- `AppData` under the current user: writable.

Do not retry failed items with tricks. Record them and finish with `admin-fixup.ps1` (self-elevating) or a `.cmd` the user can run as administrator.

## 5. Partial-failure recovery

If `Remove-Item` fails mid-tree, check whether the folder is still intact:

- Same file count/size as before → nothing was removed; safe to retry elevated later.
- Fewer files → half-deleted state. Finish the deletion elevated, or restore from backup. Never leave a half-deleted application directory, especially under `Program Files`.

## 6. Recycle bin

Use `Clear-RecycleBin -DriveLetter <C> -Force`. Do not delete `C:\$RECYCLE.BIN` contents directly — per-user bins and shell state get corrupted. Report the before/after size.

## 7. Verification and reporting

After the pass:

1. `Test-Path` every deleted path → must be false.
2. Compare `Get-PSDrive C` free space before/after. A few hundred MB of drift is normal; a large negative drift means something re-downloaded or the page file grew.
3. Confirm the "keep" list is untouched (spot-check Office, SQL CLR, licensing dirs, boot drivers).
4. Report: deleted count/MB per group, recycle bin, failures + exact ACL reason, backup path + restore command, and what was deliberately kept.

Caches (`npm-cache`, `pnpm-cache`, `uv`, `electron`, `node-gyp`, updater installers) rebuild automatically; say so, because users notice re-downloads and think something broke.

## 8. Never delete (regardless of allowlist)

`C:\Windows\Installer` (MSI patches needed for repair/uninstall), `ProgramData\Package Cache`,
MSI-tracked component folders (SQL CLR license files, Office Click-to-Run `Office 15\ClientX64`),
boot-start driver payloads (e.g. MuMu `MuMuVMMVbox\LoadedDrivers`), any licensing/activation directory,
`ProgramData\Reprise`, `SafeNet Sentinel`, `FLEXnet`, and anything from the audit's keep list.
