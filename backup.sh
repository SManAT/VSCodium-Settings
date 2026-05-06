#!/bin/bash
# Convenience script to backup VSCodium settings

DIR="$( cd "$( dirname "$0" )" && pwd )"
"$DIR/VSCodiumSync.sh" --action Backup --backup-path "$DIR/VSCodium-Backup"
