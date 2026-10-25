# Cleanup plan schema

The cleanup scripts consume one JSON file. Build it from the audit report (`dsh-app-inventory-audit` → `orphans.csv`) and the user's approval. Keep it next to the deletion log so the operation is auditable.

```json
{
  "created": "2026-10-25T16:00:00+08:00",
  "approval": "user confirmed 22 items / 340.6 MB on 2026-10-25",
  "backup_root": "D:\\C_cleanup_backup_2026-10-25",
  "recycle_drive": "C",
  "allowlist": [
    "C:\\Users\\<user>\\AppData\\Local\\",
    "C:\\Users\\<user>\\AppData\\Roaming\\",
    "C:\\ProgramData\\",
    "C:\\Program Files\\",
    "C:\\Program Files (x86)\\"
  ],
  "items": [
    { "path": "C:\\Users\\<user>\\AppData\\Local\\Steam", "group": "orphan", "risk": "low", "backup": false },
    { "path": "C:\\Program Files (x86)\\Common Files\\Steam", "group": "orphan-admin", "risk": "low", "backup": false },
    { "path": "C:\\Users\\<user>\\AppData\\Roaming\\CherryStudioDev", "group": "user-data", "risk": "high", "backup": true }
  ]
}
```

## Fields

| Field | Required | Meaning |
|---|---|---|
| `items[].path` | yes | Absolute path, no wildcards. Must sit under an `allowlist` root. |
| `items[].group` | yes | Free-form label used in logs and totals. `user-data` is special: forces backup even if `backup` is false. |
| `items[].backup` | no | `true` → copy to `backup_root` and verify byte/file counts before deleting. |
| `items[].risk` | no | `low` / `medium` / `high`; carried into logs and the final report. |
| `allowlist` | recommended | Prefixes the script accepts. Missing → defaults to the current user's AppData plus ProgramData/Program Files. |
| `backup_root` | when any backup=true | Destination on **another drive**. The original `C:\` prefix is stripped, e.g. `C:\Users\me\AppData\Roaming\X` → `<root>\Users\me\AppData\Roaming\X`. |
| `recycle_drive` | no | Drive letter for `Clear-RecycleBin` (default `C`). |
| `approval` | recommended | Human-readable record of what the user approved and when. |

## Group conventions

- `orphan` — owner software confirmed absent; user-writable location.
- `orphan-admin` — same, but under `Program Files` / `C:\` and needs elevation.
- `small-leftover` — <5 MB orphans; often can be merged into `orphan`.
- `cache` — regenerable cache of an installed app; deletion is safe but should be labelled as cache, not orphan.
- `user-data` — may contain chats, notes, models, licensing, login state. Always `backup: true`; never auto-approve.

## Rules when building the plan

1. One item per path, deduplicated, no parent/child overlap (deleting a parent makes a child fail).
2. Quote the final count and total size back to the user before executing.
3. Never add anything from the audit's "keep" list, nor `C:\Windows\Installer`, `ProgramData\Package Cache`, MSI-tracked or boot-driver payloads.
4. If a folder contains `*.sqlite`, `Notes/`, `Agents/`, models, or license files, treat it as `user-data`.
