#!/usr/bin/env bash
set -euo pipefail

make
sudo mkdir -p /Library/ScriptingAdditions/instantmini.osax/Contents/Resources
sudo cp osax/Info.plist /Library/ScriptingAdditions/instantmini.osax/Contents/Info.plist
sudo cp payload.dylib /Library/ScriptingAdditions/instantmini.osax/Contents/Resources/payload.dylib
sudo codesign -s - -f /Library/ScriptingAdditions/instantmini.osax/Contents/Resources/payload.dylib || true
sudo xattr -dr com.apple.quarantine /Library/ScriptingAdditions/instantmini.osax/Contents/Resources/payload.dylib || true
echo "Installed to /Library/ScriptingAdditions/instantmini.osax"