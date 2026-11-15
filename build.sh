#!/bin/sh
# Build the z407 CLI. The embedded Info.plist is required for CoreBluetooth access.
set -e
cd "$(dirname "$0")"
swiftc -O z407.swift -o z407 \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
echo "built ./z407"
