#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -swift-version 6 Sources/Usage.swift Tests/UsageTests.swift -o .build/usage-tests
.build/usage-tests
