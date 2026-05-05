#!/bin/bash

# VSCodium Backup and Restore Script for Linux/macOS
# Syncs extensions, settings, keybindings, tasks, and snippets

ACTION=""
BACKUP_PATH="./VSCodium-Backup"
HELP=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Detect OS and set paths
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    VSCODIUM_USER_PATH="$HOME/Library/Application Support/VSCodium/User"
    VSCODIUM_APP_PATH="$HOME/Library/Application Support/VSCodium"
else
    # Linux
    VSCODIUM_USER_PATH="$HOME/.config/VSCodium/User"
    VSCODIUM_APP_PATH="$HOME/.config/VSCodium"
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -b|--backup-path)
            BACKUP_PATH="$2"
            shift 2
            ;;
        -h|--help)
            HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Utility Functions
# ============================================================================

write_status() {
    local message="$1"
    local color="${2:-$WHITE}"
    local timestamp=$(date '+%H:%M:%S')
    echo -e "${color}[${timestamp}] ${message}${NC}"
}

show_help() {
    echo ""
    echo -e "${CYAN}VSCodium Backup and Restore Script${NC}"
    echo -e "${CYAN}====================================${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo -e "  $0 --action Backup"
    echo -e "  $0 --action Restore"
    echo -e "  $0 --action Backup --backup-path /path/to/backup"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -a, --action ACTION        Backup or Restore"
    echo -e "  -b, --backup-path PATH     Path to backup directory (default: ./VSCodium-Backup)"
    echo -e "  -h, --help                 Show this help message"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo -e "  Restore always removes existing extensions and clears all caches first."
    echo ""
}

test_prerequisites() {
    local codium_cmd
    if command -v codium &> /dev/null; then
        codium_cmd="codium"
    elif command -v code &> /dev/null; then
        codium_cmd="code"
    else
        write_status "ERROR: VSCodium/VSCode not found in PATH!" "$RED"
        return 1
    fi

    if [[ ! -d "$VSCODIUM_USER_PATH" ]]; then
        write_status "ERROR: VSCodium User directory not found!" "$RED"
        write_status "Path: $VSCODIUM_USER_PATH" "$RED"
        return 1
    fi

    export CODIUM_CMD="$codium_cmd"
    return 0
}

# ============================================================================
# Backup Functions
# ============================================================================

clear_vscodium_cache() {
    local cache_paths=(
        "$VSCODIUM_APP_PATH/Cache"
        "$VSCODIUM_APP_PATH/CachedData"
        "$VSCODIUM_APP_PATH/CachedExtensionVSIXs"
        "$VSCODIUM_APP_PATH/Code Cache"
        "$VSCODIUM_APP_PATH/GPUCache"
        "$VSCODIUM_APP_PATH/logs"
        "$VSCODIUM_USER_PATH/workspaceStorage"
        "$VSCODIUM_USER_PATH/History"
    )

    write_status "Clearing cached data..." "$YELLOW"
    for path in "${cache_paths[@]}"; do
        if [[ -d "$path" ]]; then
            if rm -rf "$path" 2>/dev/null; then
                write_status "Cleared: $path" "$YELLOW"
            else
                write_status "Could not clear: $path" "$RED"
            fi
        fi
    done
    write_status "Cache clearing done." "$GREEN"
}

backup_vscodium() {
    local backup_location="$1"

    write_status "Starting backup..." "$GREEN"

    # Create backup directory
    if [[ ! -d "$backup_location" ]]; then
        mkdir -p "$backup_location"
        write_status "Created backup directory: $backup_location" "$YELLOW"
    fi

    # Export extensions
    if $CODIUM_CMD --list-extensions > "$backup_location/extensions.txt" 2>/dev/null; then
        local ext_count=$(wc -l < "$backup_location/extensions.txt" | tr -d ' ')
        if [[ $ext_count -gt 0 ]]; then
            write_status "Exported $ext_count extensions" "$GREEN"
        else
            write_status "No extensions found" "$YELLOW"
        fi
    else
        write_status "Failed to export extensions" "$RED"
        return 1
    fi

    # Backup settings files
    local files=("settings.json" "keybindings.json" "tasks.json" "launch.json")
    for file in "${files[@]}"; do
        local source_path="$VSCODIUM_USER_PATH/$file"
        if [[ -f "$source_path" ]]; then
            if cp "$source_path" "$backup_location/$file"; then
                write_status "Backed up: $file" "$GREEN"
            else
                write_status "Failed to backup: $file" "$RED"
            fi
        else
            write_status "File not found, skipping: $file" "$YELLOW"
        fi
    done

    # Backup snippets
    local snippets_source="$VSCODIUM_USER_PATH/snippets"
    local snippets_backup="$backup_location/snippets"

    if [[ -d "$snippets_source" ]]; then
        if [[ -d "$snippets_backup" ]]; then
            rm -rf "$snippets_backup"
        fi
        if cp -r "$snippets_source" "$snippets_backup"; then
            write_status "Backed up snippets folder" "$GREEN"
        else
            write_status "Failed to backup snippets" "$RED"
        fi
    fi

    # Write backup metadata
    cat > "$backup_location/backup-info.json" <<EOF
{
  "Date": "$(date '+%Y-%m-%d %H:%M:%S')",
  "Hostname": "$(hostname)",
  "User": "$USER"
}
EOF
    write_status "Created backup metadata" "$GREEN"

    write_status "Backup completed!" "$GREEN"
    return 0
}

# ============================================================================
# Restore Functions
# ============================================================================

install_extension_with_fallback() {
    local extension_id="$1"
    local publisher="${extension_id%%.*}"
    local name="${extension_id#*.}"
    local vsix_path="/tmp/${extension_id//[^a-zA-Z0-9.-]/_}.vsix"

    # Attempt 1: default gallery (Open VSX)
    if $CODIUM_CMD --install-extension "$extension_id" --force 2>/dev/null; then
        write_status "Installed: $extension_id" "$GREEN"
        return 0
    fi
    write_status "Primary gallery failed for $extension_id - trying Open VSX direct..." "$YELLOW"

    # Attempt 2: Open VSX direct VSIX download
    local vsix_url
    if vsix_url=$(curl -s "https://open-vsx.org/api/$publisher/$name" 2>/dev/null | grep -o '"download":"[^"]*' | cut -d'"' -f4); then
        if [[ -n "$vsix_url" ]]; then
            if curl -sL "$vsix_url" -o "$vsix_path" 2>/dev/null; then
                if $CODIUM_CMD --install-extension "$vsix_path" --force 2>/dev/null; then
                    write_status "Installed: $extension_id (Open VSX direct)" "$GREEN"
                    rm -f "$vsix_path"
                    return 0
                fi
            fi
        fi
    fi
    rm -f "$vsix_path"
    write_status "Open VSX direct failed for $extension_id" "$YELLOW"

    # Attempt 3: Microsoft marketplace
    local ms_url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$publisher/vsextensions/$name/latest/vspackage"
    if curl -sL "$ms_url" -o "$vsix_path" -H "User-Agent: VSCode/1.85.0" 2>/dev/null; then
        if $CODIUM_CMD --install-extension "$vsix_path" --force 2>/dev/null; then
            write_status "Installed: $extension_id (Microsoft marketplace)" "$GREEN"
            rm -f "$vsix_path"
            return 0
        fi
    fi
    rm -f "$vsix_path"

    write_status "FAILED: $extension_id - all sources exhausted" "$RED"
    return 1
}

restore_vscodium() {
    local backup_location="$1"

    if [[ ! -d "$backup_location" ]]; then
        write_status "Backup directory not found: $backup_location" "$RED"
        return 1
    fi

    write_status "Starting restore..." "$GREEN"

    # Confirm with user
    read -p "This will sync extensions and overwrite current settings. Continue? (Y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        write_status "Restore cancelled." "$YELLOW"
        return 0
    fi

    # Sync extensions
    local extensions_file="$backup_location/extensions.txt"
    if [[ -f "$extensions_file" ]]; then
        # Read backup extensions
        local -a backup_exts=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && backup_exts+=("$line")
        done < "$extensions_file"

        # Read current extensions
        local -a current_exts=()
        if current_output=$($CODIUM_CMD --list-extensions 2>/dev/null); then
            while IFS= read -r line; do
                [[ -n "$line" ]] && current_exts+=("$line")
            done <<< "$current_output"
        fi

        # Remove extensions not in backup
        for ext in "${current_exts[@]}"; do
            if [[ ! " ${backup_exts[@]} " =~ " ${ext} " ]]; then
                if $CODIUM_CMD --uninstall-extension "$ext" --force 2>/dev/null; then
                    write_status "Removed: $ext" "$RED"
                fi
            fi
        done

        # Install missing extensions
        local success=0
        local -a failed=()
        for ext in "${backup_exts[@]}"; do
            if [[ " ${current_exts[@]} " =~ " ${ext} " ]]; then
                write_status "Already installed: $ext" "$GRAY"
            elif install_extension_with_fallback "$ext"; then
                ((success++))
            else
                failed+=("$ext")
            fi
        done

        write_status "Extensions: $success installed, ${#failed[@]} failed" "$CYAN"
        if [[ ${#failed[@]} -gt 0 ]]; then
            write_status "Failed: ${failed[*]}" "$RED"
        fi
    fi

    clear_vscodium_cache

    # Restore settings files
    local files=("settings.json" "keybindings.json" "tasks.json" "launch.json")
    for file in "${files[@]}"; do
        local backup_file="$backup_location/$file"
        if [[ -f "$backup_file" ]]; then
            if cp "$backup_file" "$VSCODIUM_USER_PATH/$file"; then
                write_status "Restored: $file" "$GREEN"
            else
                write_status "Failed to restore: $file" "$RED"
            fi
        fi
    done

    # Restore snippets
    local snippets_backup="$backup_location/snippets"
    if [[ -d "$snippets_backup" ]]; then
        local snippets_target="$VSCODIUM_USER_PATH/snippets"
        if [[ -d "$snippets_target" ]]; then
            rm -rf "$snippets_target"
        fi
        if cp -r "$snippets_backup" "$snippets_target"; then
            write_status "Restored snippets" "$GREEN"
        else
            write_status "Failed to restore snippets" "$RED"
        fi
    fi

    write_status "Restore completed!" "$GREEN"
    return 0
}

# ============================================================================
# Main execution
# ============================================================================

if [[ "$HELP" == true ]] || [[ -z "$ACTION" ]]; then
    show_help
    if [[ -z "$ACTION" ]]; then
        write_status "ERROR: No action specified!" "$RED"
        exit 1
    fi
    exit 0
fi

if ! test_prerequisites; then
    exit 1
fi

case "$ACTION" in
    Backup)
        if backup_vscodium "$BACKUP_PATH"; then
            write_status "Script completed successfully!" "$GREEN"
            exit 0
        else
            exit 1
        fi
        ;;
    Restore)
        if restore_vscodium "$BACKUP_PATH"; then
            write_status "Script completed successfully!" "$GREEN"
            exit 0
        else
            exit 1
        fi
        ;;
    *)
        write_status "Invalid action: $ACTION" "$RED"
        show_help
        exit 1
        ;;
esac
