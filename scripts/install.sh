#!/bin/zsh
set -euo pipefail
CELL_ROOT="${0:A:h:h}"
"$CELL_ROOT/scripts/build.sh"
if pgrep -x Cell >/dev/null; then
    print -u2 'Quit Cell before installing an update.'
    exit 1
fi
if [[ -d /Applications/Cell.app ]]; then
    CELL_BACKUP="$HOME/Library/Application Support/Cell/Backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$CELL_BACKUP"
    ditto /Applications/Cell.app "$CELL_BACKUP/Cell.app"
fi
ditto "$CELL_ROOT/build/Cell.app" /Applications/Cell.app
print 'Installed /Applications/Cell.app'
