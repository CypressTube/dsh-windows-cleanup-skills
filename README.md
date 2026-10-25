# dsh-windows-cleanup-skills

Two [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) skills for auditing installed Windows software and safely removing folders left behind by software that no longer exists or is unused.

两个 DSH 技能：盘点 Windows 已安装软件、找出「软件已不存在/未使用」的残留文件夹，并在确认后安全清理。

| Skill | Mode | What it does |
|---|---|---|
| `dsh-app-inventory-audit` | read-only | Builds an install inventory (registry uninstall keys, services, Run keys, App Paths, shortcuts, AppX, UserAssist), scans Program Files / ProgramData / AppData folders, cross-matches them, and outputs candidate leftovers with evidence and risk. Never deletes. |
| `dsh-orphan-folder-cleanup` | destructive, guarded | Deletes a **user-confirmed** path list from a plan JSON: allowlist validation, protected-path refusal, backup-before-delete with byte/file verification, per-item logging, non-admin failure handling, recycle-bin clearing, post-delete verification and restore. |

## Install / 安装

```powershell
git clone https://github.com/MrCypressBai/dsh-windows-cleanup-skills.git
$dest = Join-Path $env:USERPROFILE '.dsh\skills'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item .\dsh-windows-cleanup-skills\dsh-* $dest -Recurse -Force
```

Or link the folders so `git pull` keeps them updated / 或用目录联接保持自动更新:

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\.dsh\skills\dsh-app-inventory-audit" -Target "$PWD\dsh-windows-cleanup-skills\dsh-app-inventory-audit"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.dsh\skills\dsh-orphan-folder-cleanup" -Target "$PWD\dsh-windows-cleanup-skills\dsh-orphan-folder-cleanup"
```

DSH loads user skills from `%USERPROFILE%\.dsh\skills\<name>\SKILL.md` (and project skills from `<repo>/.dsh/skills/`). Restart the session or wait for the filesystem watcher to pick them up.

## Usage / 用法

1. Ask in DSH: “列出 C 盘和 D 盘已安装的软件，找出软件已不存在的残留文件夹” → `dsh-app-inventory-audit` triggers.
2. Review the Markdown report + `orphans.csv`; approve a path list.
3. `dsh-orphan-folder-cleanup` builds a plan JSON from the approved list, dry-runs it, backs up user-data groups, deletes, and reports what was freed / what needs admin.

## Safety model / 安全模型

- Audit is strictly read-only.
- Cleanup refuses drive roots, wildcards, reparse points, protected OS/installer/licensing paths, and anything outside the plan allowlist.
- User data (sqlite, notes, models, login state, licensing) is backed up and verified before deletion; `restore-backup.ps1` restores it.
- Items under `Program Files` / `C:\` normally need elevation; the scripts log them as failed and provide a self-elevating follow-up instead of pretending success.
- Known false positives (Office Click-to-Run `Office 15`, SQL CLR license files, InstallAnywhere `Zero G Registry`, ADINA licensing dirs, MuMu boot driver, Web Deploy/IIS, COMSOL LiveLink, Bonjour dual dirs, `Windows\Installer`, Package Cache) are documented in the audit skill's `references/false-positive-traps.md`.

## Requirements / 环境

- Windows 10/11, PowerShell 7 (`pwsh`).
- Non-admin sessions are fine (admin-only leftovers are reported for a later elevated pass).
- No WMI/CIM dependency, works when `Get-CimInstance` is blocked.

## Layout

```
dsh-app-inventory-audit/
  SKILL.md
  agents/openai.yaml
  scripts/{collect-evidence,scan-folders,find-orphans}.ps1
  references/{evidence-sources,false-positive-traps}.md
dsh-orphan-folder-cleanup/
  SKILL.md
  agents/openai.yaml
  scripts/{execute-cleanup,admin-fixup,restore-backup}.ps1
  references/{plan-schema,safety-rules}.md
```

## License

MIT — see [LICENSE](LICENSE).
