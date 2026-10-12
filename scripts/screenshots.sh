#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build/ModuleCache docs/images
read -r -a includes <<< "$(pkg-config --cflags freerdp3 freerdp-client3 winpr3)"
read -r -a libraries <<< "$(pkg-config --libs freerdp3 freerdp-client3 winpr3)"
clang -fobjc-arc -fmodules -fmodules-cache-path=build/ModuleCache -O2 \
  -Wall -Wextra -Wno-unused-parameter "${includes[@]}" -ISources \
  scripts/render-screenshots.m Sources/QDProfile.m Sources/QDSession.m Sources/QDDesktopView.m \
  -framework AppKit -framework Security -framework QuartzCore "${libraries[@]}" \
  -o build/render-screenshots
build/render-screenshots
