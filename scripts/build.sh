#!/bin/zsh
set -euo pipefail
CELL_ROOT="${0:A:h:h}"
CELL_SDK="${CELL_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [[ ! -d "$CELL_SDK" ]]; then CELL_SDK="$(xcrun --show-sdk-path)"; fi
export SDKROOT="$CELL_SDK"
cd "$CELL_ROOT"
swift build -c release --product Cell --scratch-path build/spm -Xswiftc -sdk -Xswiftc "$CELL_SDK" -Xcc -isysroot -Xcc "$CELL_SDK"
CELL_APP="$CELL_ROOT/build/Cell.app"
mkdir -p "$CELL_APP/Contents/MacOS" "$CELL_APP/Contents/Resources"
cp build/spm/release/Cell "$CELL_APP/Contents/MacOS/Cell"
cp Resources/Info.plist "$CELL_APP/Contents/Info.plist"
swiftc -sdk "$CELL_SDK" -parse-as-library Sources/Cell/CellIcon.swift scripts/make-icon.swift -o build/make-icon
build/make-icon "$CELL_APP/Contents/Resources"
cp "$CELL_APP/Contents/Resources/AppIcon.iconset/icon_512x512@2x.png" docs/assets/cell-icon.png
codesign --force --sign - --options runtime "$CELL_APP"
print "Built $CELL_APP"
