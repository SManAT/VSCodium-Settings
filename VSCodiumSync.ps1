param(
    [string]$Action,
    [string]$BackupPath = ".\VSCodium-Backup",
    [switch]$Help
)

$VSCodiumUserPath = "$env:APPDATA\VSCodium\User"
$VSCodiumAppPath  = "$env:APPDATA\VSCodium"

function Write-Status {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

function Show-Help {
    Write-Host ""
    Write-Host "VSCodium Backup and Restore Script" -ForegroundColor Cyan
    Write-Host "==================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\VSCodiumSync.ps1 -Action Backup" -ForegroundColor Green
    Write-Host "  .\VSCodiumSync.ps1 -Action Restore" -ForegroundColor Green
    Write-Host ""
    Write-Host "Notes:" -ForegroundColor Yellow
    Write-Host "  Restore always removes existing extensions and clears all caches first." -ForegroundColor White
    Write-Host ""
}

function Test-Prerequisites {
    $codium = Get-Command codium -ErrorAction SilentlyContinue
    if (-not $codium) {
        Write-Host "ERROR: VSCodium not found in PATH!" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $VSCodiumUserPath)) {
        Write-Host "ERROR: VSCodium User directory not found!" -ForegroundColor Red
        Write-Host "Path: $VSCodiumUserPath" -ForegroundColor Red
        return $false
    }

    return $true
}

function Clear-VSCodiumCache {
    $cachePaths = @(
        "$VSCodiumAppPath\Cache",
        "$VSCodiumAppPath\CachedData",
        "$VSCodiumAppPath\CachedExtensionVSIXs",
        "$VSCodiumAppPath\Code Cache",
        "$VSCodiumAppPath\GPUCache",
        "$VSCodiumAppPath\logs",
        "$VSCodiumUserPath\workspaceStorage",
        "$VSCodiumUserPath\History"
    )

    Write-Status "Clearing cached data..." "Yellow"
    foreach ($path in $cachePaths) {
        if (Test-Path $path) {
            try {
                Remove-Item $path -Recurse -Force -ErrorAction Stop
                Write-Status "Cleared: $path" "Yellow"
            }
            catch {
                Write-Status "Could not clear: $path - $($_.Exception.Message)" "Red"
            }
        }
    }
    Write-Status "Cache clearing done." "Green"
}


function Backup-VSCodium {
    param([string]$BackupLocation)

    Write-Status "Starting backup..." "Green"

    if (-not (Test-Path $BackupLocation)) {
        New-Item -Path $BackupLocation -ItemType Directory -Force | Out-Null
        Write-Status "Created backup directory: $BackupLocation" "Yellow"
    }

    # Export extensions
    try {
        $extensions = codium --list-extensions
        if ($extensions) {
            $extensions | Out-File "$BackupLocation\extensions.txt" -Encoding UTF8
            Write-Status "Exported $($extensions.Count) extensions" "Green"
        } else {
            "" | Out-File "$BackupLocation\extensions.txt" -Encoding UTF8
            Write-Status "No extensions found" "Yellow"
        }
    }
    catch {
        Write-Status "Failed to export extensions: $($_.Exception.Message)" "Red"
        return $false
    }

    # Backup settings files
    $files = @("settings.json", "keybindings.json", "tasks.json", "launch.json")

    foreach ($file in $files) {
        $sourcePath = "$VSCodiumUserPath\$file"
        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath "$BackupLocation\$file" -Force
            Write-Status "Backed up: $file" "Green"
        } else {
            Write-Status "File not found, skipping: $file" "Yellow"
        }
    }

    # Backup snippets
    $snippetsSource = "$VSCodiumUserPath\snippets"
    $snippetsBackup = "$BackupLocation\snippets"

    if (Test-Path $snippetsSource) {
        if (Test-Path $snippetsBackup) {
            Remove-Item $snippetsBackup -Recurse -Force
        }
        Copy-Item $snippetsSource $snippetsBackup -Recurse -Force
        Write-Status "Backed up snippets folder" "Green"
    }

    # Write backup metadata
    @{
        Date         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        UserName     = $env:USERNAME
    } | ConvertTo-Json | Out-File "$BackupLocation\backup-info.json" -Encoding UTF8

    Write-Status "Backup completed!" "Green"
    return $true
}

function Install-ExtensionWithFallback {
    param([string]$ExtensionId)

    $parts     = $ExtensionId -split '\.', 2
    $publisher = $parts[0]
    $name      = $parts[1]
    $vsixPath  = "$env:TEMP\$($ExtensionId -replace '[^a-zA-Z0-9.\-]','_').vsix"

    # Attempt 1: default gallery (Open VSX)
    codium --install-extension $ExtensionId --force 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Installed: $ExtensionId" "Green"
        return $true
    }
    Write-Status "Primary gallery failed for $ExtensionId - trying Open VSX direct..." "Yellow"

    # Attempt 2: Open VSX direct VSIX download
    $installed = $false
    try {
        $meta    = Invoke-RestMethod "https://open-vsx.org/api/$publisher/$name" -ErrorAction Stop
        $vsixUrl = $meta.files.download
        if ($vsixUrl) {
            Invoke-WebRequest $vsixUrl -OutFile $vsixPath -ErrorAction Stop
            codium --install-extension $vsixPath --force 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Installed: $ExtensionId (Open VSX direct)" "Green"
                $installed = $true
            }
        }
    } catch {
        Write-Status "Open VSX direct failed for $ExtensionId - $($_.Exception.Message)" "Yellow"
    } finally {
        Remove-Item $vsixPath -Force -ErrorAction SilentlyContinue
    }
    if ($installed) { return $true }
    Write-Status "Trying Microsoft marketplace for $ExtensionId..." "Yellow"

    # Attempt 3: Microsoft marketplace
    try {
        $msUrl = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$name/latest/vspackage"
        Invoke-WebRequest $msUrl -OutFile $vsixPath -UserAgent "VSCode/1.85.0" -ErrorAction Stop
        codium --install-extension $vsixPath --force 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Status "Installed: $ExtensionId (Microsoft marketplace)" "Green"
            $installed = $true
        }
    } catch {
        Write-Status "Microsoft marketplace failed for $ExtensionId - $($_.Exception.Message)" "Yellow"
    } finally {
        Remove-Item $vsixPath -Force -ErrorAction SilentlyContinue
    }
    if ($installed) { return $true }

    Write-Status "FAILED: $ExtensionId - all sources exhausted" "Red"
    return $false
}

function Restore-VSCodium {
    param([string]$BackupLocation)

    if (-not (Test-Path $BackupLocation)) {
        Write-Status "Backup directory not found: $BackupLocation" "Red"
        return $false
    }

    Write-Status "Starting restore..." "Green"

    $confirmation = Read-Host "This will sync extensions and overwrite current settings. Continue? (Y/N)"
    if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
        Write-Status "Restore cancelled." "Yellow"
        return $false
    }

    # Sync extensions
    $extensionsFile = "$BackupLocation\extensions.txt"
    if (Test-Path $extensionsFile) {
        $backupExts  = @(Get-Content $extensionsFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
        $currentExts = @(codium --list-extensions 2>$null | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })

        foreach ($ext in $currentExts) {
            if ($ext -notin $backupExts) {
                codium --uninstall-extension $ext --force 2>$null | Out-Null
                Write-Status "Removed: $ext" "Red"
            }
        }

        $success = 0
        $failed  = @()
        foreach ($ext in $backupExts) {
            if ($ext -in $currentExts) {
                Write-Status "Already installed: $ext" "Gray"
            } elseif (Install-ExtensionWithFallback $ext) {
                $success++
            } else {
                $failed += $ext
            }
        }

        Write-Status "Extensions: $success installed, $($failed.Count) failed" "Cyan"
        if ($failed.Count -gt 0) {
            Write-Status "Failed: $($failed -join ', ')" "Red"
        }
    }

    Clear-VSCodiumCache

    # Restore settings files
    $files = @("settings.json", "keybindings.json", "tasks.json", "launch.json")

    foreach ($file in $files) {
        $backupFile = "$BackupLocation\$file"
        if (Test-Path $backupFile) {
            Copy-Item $backupFile "$VSCodiumUserPath\$file" -Force
            Write-Status "Restored: $file" "Green"
        }
    }

    # Restore snippets
    $snippetsBackup = "$BackupLocation\snippets"
    if (Test-Path $snippetsBackup) {
        $snippetsTarget = "$VSCodiumUserPath\snippets"
        if (Test-Path $snippetsTarget) {
            Remove-Item $snippetsTarget -Recurse -Force
        }
        Copy-Item $snippetsBackup $snippetsTarget -Recurse -Force
        Write-Status "Restored snippets" "Green"
    }

    Write-Status "Restore completed!" "Green"
    return $true
}

# Main execution
if ($Help -or (-not $Action)) {
    Show-Help
    if (-not $Action) {
        Write-Host "ERROR: No action specified!" -ForegroundColor Red
    }
    exit 0
}

if (-not (Test-Prerequisites)) {
    exit 1
}

switch ($Action) {
    "Backup" {
        $result = Backup-VSCodium $BackupPath
        if (-not $result) { exit 1 }
    }
    "Restore" {
        $result = Restore-VSCodium $BackupPath
        if (-not $result) { exit 1 }
    }
    default {
        Write-Host "Invalid action: $Action" -ForegroundColor Red
        Show-Help
        exit 1
    }
}

Write-Status "Script completed successfully!" "Green"
