#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:?kernel dir}"

REPO="${BBG_REPO:-https://github.com/vc-teahouse/Baseband-guard.git}"
REF="${BBG_REF:-}"

git clone --depth=1 ${REF:+--branch "$REF"} "$REPO" "$KERNEL_DIR/Baseband-guard"
cd "$KERNEL_DIR"
sh Baseband-guard/setup.sh
echo "CONFIG_BBG=y" >> "$KERNEL_DIR/common/CoreShift.fragment"
