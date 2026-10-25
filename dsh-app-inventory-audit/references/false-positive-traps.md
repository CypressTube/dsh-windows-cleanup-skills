# False-positive traps: folders that look orphaned but are live

Check this list before calling anything an orphan. Each row cost real debugging time.

| Folder | Looks like | Actually |
|---|---|---|
| `Program Files\Microsoft Office 15\ClientX64` | Office 2013 leftover | **Office Click-to-Run infrastructure** used by Microsoft 365. `OfficeClickToRun.exe` is signed and refreshed on updates; `ClickToRunSvc` runs from it. Deleting breaks Office update/repair. |
| `Program Files\Microsoft SQL Server\90\Shared\Resources` | SQL Server 2005 leftover | License RTF files shipped by the installed `Microsoft System CLR Types for SQL Server 2019` MSI. MSI-tracked → deleting triggers repair prompts. |
| `Program Files\Zero G Registry` | Installer junk | InstallAnywhere uninstall registry (`.com.zerog.registry.xml`) for **Altair HyperMesh/SimLab** products; removing it breaks their uninstall. |
| `Program Files\IIS`, `Program Files (x86)\IIS` | Disabled IIS feature | Owned by the installed **Microsoft Web Deploy 4.0**; the IIS Windows feature may be absent while these folders are live. Uninstall Web Deploy properly instead. |
| `Program Files\Autodesk` | Autodesk leftover | Contains `ApplicationPlugins\LiveLinkforCOMSOL.bundle` — the installed **COMSOL LiveLink** add-in (also referenced from `HKLM\SOFTWARE\SolidWorks\Addins`). |
| `Program Files\Bonjour` vs `Program Files (x86)\Bonjour` | Duplicate, one is leftover | Both can be real: the MSI registers the x86 path while the **Bonjour Service ImagePath points at the 64-bit path**. Resolve the service before touching either. |
| `Program Files\MuMuVMMVbox` | Emulator leftover after uninstall | Holds `LoadedDrivers\MuMuVMMDrv.sys`, a **boot-start driver** (`Start=1`) and the MuMu virtual display adapter is still registered. Delete via Device Manager/driver uninstall, never by folder. |
| `ProgramData\Reprise`, `ProgramData\SafeNet Sentinel`, `ProgramData\Bentley`, `HKCU\SOFTWARE\Bentley\Adina` | Random vendor leftovers | **ADINA 9.x licensing/config** (RLM + Sentinel, Bentley-branded desktop client). ADINA can be installed elsewhere while these remain required. |
| `Program Files\Windows Sidebar`, `Windows NT`, `Windows Mail`, `Windows Photo Viewer`, `Uninstall Information` | Old Windows folders | OS-managed shell components or hidden installer bookkeeping. Leave them; they are 0 bytes or refreshed by Windows Update. |
| `ProgramData\USOShared`, `USOPrivate`, `SoftwareDistribution`, `Microsoft\*`, `Packages`, `regid.*` | Update/leftover cache | Windows servicing and OS state. |
| `ProgramData\Package Cache`, `C:\Windows\Installer` | Huge "orphan" folders | MSI payload caches required for repair/uninstall. Never script-delete; use `msizap`/`PatchCleaner`-class tooling with backups if truly needed. |
| `Users\Public\Documents|Pictures|Videos|Music`, `desktop.ini`, `AccountPictures` | Empty user folders | OS shell folders. |
| `ProgramData\ChocolateyHttpCache`, `ProgramData\chocolatey` | Package cache leftover | Live Chocolatey. `.locks` denies non-admin deletes; leave it or run elevated. |
| `AppData\Local\<Vendor>` with only `Cache`, `GPUCache`, `blob_storage` | Orphan | Chromium/Electron **profile of an installed app** — resolve the app first. Cache-only deletion is fine, but check for `Local Storage` / `Login Data` / `*.sqlite` and warn if a login or user data could be lost. |
| Folders named `cache`, `Cache`, `Common`, `Shared`, `Client`, `Data` | Match by name | Generic tokens produce false "live" hits; match **full paths** first, then distinct vendor tokens. |
| Non-empty on disk, 0 bytes reported | Empty | ACL denied. Re-check with elevated read or `Get-Acl` before declaring it empty. |
| AppX/Store apps | No uninstall key | They appear in the AppX repo, not the uninstall keys; data lives in `AppData\Local\Packages\<PackageFamilyName>`. |

## Ordering rule

When evidence conflicts, trust this order:
1. service `ImagePath` / Run key / shortcut target pointing into the folder
2. uninstall entry `InstallLocation` / `DisplayIcon`
3. App Paths / AppX package
4. name appears in install inventory
5. name token appears somewhere (weak — always verify by hand)

Folder size and "last modified years ago" never override a live reference. Conversely, an old timestamp alone never proves orphanhood.
