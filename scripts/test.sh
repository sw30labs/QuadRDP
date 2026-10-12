#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
mkdir -p build/test-data build/ModuleCache
test_dir="$(mktemp -d "$PWD/build/test-data/run.XXXXXX")"
export QUADRDP_DATA_DIR="$test_dir"
openssl_bin="$(brew --prefix openssl@3)/bin/openssl"
"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -keyout build/test-data/key.pem \
  -out build/test-data/cert.pem -days 1 -subj /CN=localhost \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' > build/test-data/cert-generation.log 2>&1
"$openssl_bin" req -x509 -newkey rsa:2048 -nodes -keyout build/test-data/key2.pem \
  -out build/test-data/cert2.pem -days 1 -subj /CN=localhost \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' >> build/test-data/cert-generation.log 2>&1
read -r -a includes <<< "$(pkg-config --cflags freerdp3 freerdp-client3 winpr3)"
read -r -a libraries <<< "$(pkg-config --libs freerdp3 freerdp-client3 winpr3)"
clang -fobjc-arc -fmodules -fmodules-cache-path=build/ModuleCache -g -O1 \
  -Wall -Wextra -Wno-unused-parameter "${includes[@]}" -ISources \
  Tests/Tests.m Sources/QDProfile.m Sources/QDSession.m Sources/QDDesktopView.m \
  -framework AppKit -framework Security "${libraries[@]}" -o build/QuadRDPTests
WLOG_LEVEL=ERROR build/QuadRDPTests > build/test-data/results.log 2>&1 || { cat build/test-data/results.log; exit 1; }
rg '^(PASS|All )' build/test-data/results.log
