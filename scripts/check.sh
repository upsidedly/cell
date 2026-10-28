#!/bin/zsh
set -euo pipefail
CELL_ROOT="${0:A:h:h}"
CELL_SDK="${CELL_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [[ ! -d "$CELL_SDK" ]]; then CELL_SDK="$(xcrun --show-sdk-path)"; fi
cd "$CELL_ROOT"
swift build -c debug --product CellChecks --scratch-path build/checks -Xswiftc -sdk -Xswiftc "$CELL_SDK" -Xswiftc -warnings-as-errors -Xcc -isysroot -Xcc "$CELL_SDK"
build/checks/debug/CellChecks
