#!/bin/bash
# 不依赖 Xcode：用 swiftc 直接编译 Core 和音效合成器，跑一遍规则自检。macOS 和 Linux 都可以。
set -e
cd "$(dirname "$0")"
APP=../../HumanContent
OUT=$(mktemp -d)
swiftc -swift-version 5 -O "$APP"/Core/*.swift "$APP"/Audio/Synth.swift shim.swift main.swift -o "$OUT/core-checks"
cd "$OUT" && ./core-checks
