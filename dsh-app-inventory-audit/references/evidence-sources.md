# Evidence sources and how to read them

All collectors are WMI-free because harness sandboxes often block `Get-CimInstance`.

## Registry uninstall entries (the inventory backbone)

```
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*          (64-bit)
HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*  (32-bit)
HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*          (per-user)
```

Fields that prove an install owns a folder: `DisplayName`, `InstallLocation`, `DisplayIcon` (strip `,0` icon index), `UninstallString`.

Caveat: runtime/component entries (`.NET Runtime`, `Visual C++ Redistributable`, SDK manifests) flood the list — several hundred entries on a dev machine is normal and not an error.

## AppX / MSIX

```
HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications
```

Store apps install under `C:\Program Files\WindowsApps` (ACL-protected, list-only) and keep data in `AppData\Local\Packages\<PackageFamilyName>`.

## Services (no WMI)

`HKLM:\SYSTEM\CurrentControlSet\Services\*` → `ImagePath` (or `ServiceDll` for svchost services). A service whose `ImagePath` points into a folder makes that folder LIVE. Do not treat `Start=4` (disabled) as proof it is unused — installed drivers may still be required.

## Startup entries

`Run` keys under HKLM, `HKLM:\SOFTWARE\WOW6432Node`, HKCU. Startup folder shortcuts are covered by the shortcut scan.

## App Paths

`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\*` — the default value is the exe path; proves a program is registered for `Start → Run`.

## Shortcuts

Resolve `.lnk` targets with `WScript.Shell` (`(New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath`). Search Desktop, Public Desktop, both Start Menu trees, Quick Launch. Shortcut targets are one of the strongest install signals.

A shortcut whose target is missing is itself an orphan artifact (safe to remove, zero size).

## UserAssist (weak last-run signal)

```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{CEBFF5CD-...-41749EA}\Count   (exe launches)
HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{F4E57C4B-...-443BCFE33D9F}\Count   (shortcut launches)
```

Value names are ROT13-encoded paths. Binary layout (Win7+): offset 4 = run count (Int32), offset 60 = last-run FILETIME (Int64). Decode with `[datetime]::FromFileTimeUtc($ft).ToLocalTime()`.

Limitations: it is frequently reset by cleanup tools, so absence ≠ unused, and the newest entry may be months old while the app runs daily. Never present it as authoritative.

## Prefetch

`C:\Windows\Prefetch\*.pf` gives launch timestamps, but Windows often disables it (especially on SSDs or after privacy tweaks). If `Get-ChildItem C:\Windows\Prefetch -Filter *.pf` returns nothing, fall back to UserAssist + file mtimes and say usage evidence is limited.

## Filesystem timestamps

For each candidate folder record: recursive file count, total bytes, newest file `LastWriteTime`, folder `LastWriteTime`. Newest-file time is the best cheap staleness proxy. Empty results on a protected folder mean *unreadable*, not *empty* — confirm with `Test-Path` and an ACL check before calling a folder 0-byte.

## Data-drive inventory

Enumerate level-1 and level-2 directories on D:/E:/G: (skip `$RECYCLE.BIN`, `System Volume Information`, `Recovery`). This is how you prove an app moved to another drive: the exe lives there while its data folder remains on C:.
