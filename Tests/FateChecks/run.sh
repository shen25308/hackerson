#!/bin/bash
# 不依赖 Xcode：用 swiftc 编译 Core 和这份自检，跑 50 局四夜之约。macOS 和 Linux 都可以。
set -e
cd "$(dirname "$0")"
APP=../../HumanContent
OUT=$(mktemp -d)
swiftc -swift-version 5 -O "$APP"/Core/*.swift ../CoreChecks/shim.swift main.swift -o "$OUT/fate-checks"
"$OUT/fate-checks" "$(cd "$APP/Resources" && pwd)/fate.json"
