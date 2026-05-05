# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VSCodium settings backup and restore utility for Windows. It synchronizes VSCodium configuration, extensions, and other settings between the live installation and a git-tracked backup directory.

**Main purpose:** Enable version control and reproduction of VSCodium configurations across machines.

## Running the Script

### Windows (PowerShell)

**Primary Entry Points**

- **Backup:** `.\VSCodiumSync.ps1 -Action Backup`
  - Exports installed extensions list to `extensions.txt`
  - Copies settings files: `settings.json`, `keybindings.json`, `tasks.json`, `launch.json`
  - Copies snippets directory
  - Creates `backup-info.json` with metadata (date, computer name, username)

- **Restore:** `.\VSCodiumSync.ps1 -Action Restore`
  - Prompts for confirmation before proceeding
  - Syncs extensions: uninstalls any not in backup, installs missing ones
  - Clears VSCodium caches
  - Overwrites settings files with backed-up versions
  - Restores snippets directory

- **Help:** `.\VSCodiumSync.ps1 -Help`

**Batch Wrappers**

- `Backup.bat` — runs backup with default paths, pauses for user visibility
- `Restore.bat` — runs restore with default paths, pauses for user visibility

### Linux / macOS (Bash)

**Primary Entry Points**

- **Backup:** `./VSCodiumSync.sh --action Backup`
- **Restore:** `./VSCodiumSync.sh --action Restore`
- **Help:** `./VSCodiumSync.sh --help`

**Options**

- `-a, --action ACTION` — Backup or Restore (required)
- `-b, --backup-path PATH` — Path to backup directory (default: `./VSCodium-Backup`)
- `-h, --help` — Show help message

**Shell Wrappers**

- `backup.sh` — runs backup with default paths
- `restore.sh` — runs restore with default paths

Make sure scripts are executable:
```bash
chmod +x VSCodiumSync.sh backup.sh restore.sh
```

**Platform Detection**

The bash script automatically detects the OS and uses the correct paths:
- **macOS:** `~/Library/Application Support/VSCodium/User`
- **Linux:** `~/.config/VSCodium/User`

It supports both `codium` and `code` (VS Code) commands.

## Code Architecture

The script is organized around these core functions:

**Setup & Validation**
- `Test-Prerequisites` — checks VSCodium is in PATH and user directory exists
- `Write-Status` — utility for timestamped, colored console output

**Backup Operations**
- `Backup-VSCodium` — orchestrates exporting extensions, copying settings, and writing metadata
- Extensions are exported via `codium --list-extensions` to `extensions.txt` (one per line, trimmed)

**Restore Operations**
- `Restore-VSCodium` — orchestrates extension sync, cache clearing, and settings restoration
- `Install-ExtensionWithFallback` — installs extensions with three fallback strategies:
  1. Default gallery (Open VSX via `codium --install-extension`)
  2. Open VSX direct VSIX download from `https://open-vsx.org/api/{publisher}/{name}`
  3. Microsoft marketplace VSIX download with VS Code user agent header
  - Each failed attempt is logged; only silenced on success

**Cache Clearing**
- `Clear-VSCodiumCache` — removes 8 standard cache locations (Cache, CachedData, CachedExtensionVSIXs, etc.)
- Called during restore to ensure clean state

## Key Implementation Details

**Extension Sync Logic:**
- Read current extensions via `codium --list-extensions`
- Read backed-up extensions from `extensions.txt`
- Uninstall any extensions present locally but not in backup
- Install all extensions in backup (skip if already present)
- Track success/failure counts and list failed extensions at the end

**Path Variables:**
- `$VSCodiumUserPath = "$env:APPDATA\VSCodium\User"` — where settings/keybindings/snippets live
- `$VSCodiumAppPath = "$env:APPDATA\VSCodium"` — where cache directories are located

**Exit Codes:**
- `0` — success
- `1` — failure (missing prerequisites, failed operations, etc.)

## Modifications and Testing

**Before modifying extension fallback logic:**
- Test against extensions in `VSCodium-Backup/extensions.txt`
- Remember that Open VSX and Microsoft marketplace can have availability/API differences
- The VSIX filename is sanitized: `$($ExtensionId -replace '[^a-zA-Z0-9.\-]','_').vsix`

**Before modifying paths or cache locations:**
- Verify they match current VSCodium installation (paths may change between versions)
- Test on a machine where VSCodium is installed to confirm directories exist

**Adding new backup targets:**
- Update the `$files` array in `Backup-VSCodium` for new config files
- Update the corresponding restore loop in `Restore-VSCodium`
- Consider whether to add cache clearing for new locations in `Clear-VSCodiumCache`

## Known Constraints

- **VSCodium/VSCode in PATH required:** Script checks for `codium` or `code` command; fails if not available
- **User interaction:** Restore operation requires user confirmation before proceeding
- **Extension installation can be slow:** Fallback downloads from multiple sources; large extension lists may take time
- **Bash script requires curl:** The Linux/macOS version uses `curl` for extension fallback downloads
- **Temporary files:** Both scripts may create temporary VSIX files in `/tmp` (Linux) or `%TEMP%` (Windows) during extension installation
