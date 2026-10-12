#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! pkg-config --atleast-version=3.0 freerdp3 freerdp-client3 winpr3; then
  echo "Install dependencies with: brew install freerdp pkg-config" >&2
  exit 1
fi
mkdir -p build/QuadRDP.app/Contents/{MacOS,Resources} build/ModuleCache
deployment_target="${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion | cut -d. -f1).0}"
read -r -a includes <<< "$(pkg-config --cflags freerdp3 freerdp-client3 winpr3)"
read -r -a libraries <<< "$(pkg-config --libs freerdp3 freerdp-client3 winpr3)"
clang -fobjc-arc -fmodules -fmodules-cache-path=build/ModuleCache -O2 -g \
  "-mmacosx-version-min=$deployment_target" -Wall -Wextra -Wno-unused-parameter \
  "${includes[@]}" Sources/*.m -framework AppKit -framework Security \
  "${libraries[@]}" -o build/QuadRDP
cp build/QuadRDP build/QuadRDP.app/Contents/MacOS/QuadRDP
cp Resources/Info.plist build/QuadRDP.app/Contents/Info.plist
cp Resources/QuadRDP.icns build/QuadRDP.app/Contents/Resources/QuadRDP.icns
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $deployment_target" build/QuadRDP.app/Contents/Info.plist
# Desktop file providers can add FinderInfo to newly created bundles; codesign rejects it.
xattr -dr com.apple.FinderInfo build/QuadRDP.app 2>/dev/null || true
xattr -dr com.apple.ResourceFork build/QuadRDP.app 2>/dev/null || true
codesign --force --sign - build/QuadRDP.app
echo "Built: $PWD/build/QuadRDP.app"
