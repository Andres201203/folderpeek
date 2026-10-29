#!/bin/zsh
# Compiles the pure-logic sources with the test runner and runs it.
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
swiftc -swift-version 5 -target arm64-apple-macos26.0 \
  Sources/Layout.swift Sources/FolderReader.swift Tests/main.swift -o .build/tests
.build/tests
