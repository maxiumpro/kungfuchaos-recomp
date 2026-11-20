#!/bin/zsh
# Builds the Kung Fu Chaos launcher (macOS 14+, Apple Silicon). Run on the Mac: zsh build.sh
set -e
cd "$(dirname "$0")"
swiftc -O -parse-as-library KFCLauncher.swift -o KFCLauncher
echo "Done: $(pwd)/KFCLauncher"
