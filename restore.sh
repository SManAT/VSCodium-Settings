#!/bin/bash
# Convenience script to restore VSCodium settings

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$DIR/VSCodiumSync.sh" --action Restore --backup-path "$DIR/VSCodium-Backup"
