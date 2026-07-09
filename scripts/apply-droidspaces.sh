#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:?kernel dir}"

REPO="${DROIDSPACES_REPO:-https://github.com/ravindu644/Droidspaces-OSS.git}"

git clone --depth=1 "$REPO" "$KERNEL_DIR/Droidspaces"

KVER=$(make -C "$KERNEL_DIR/common" kernelversion 2>/dev/null || echo "6.6")
if echo "$KVER" | grep -qE "^6\.(1[2-9]|[2-9][0-9])"; then
  PATCH_DIR="$KERNEL_DIR/Droidspaces/Documentation/resources/kernel-patches/GKI/6.12"
  SLOT="${DROIDSPACES_SYSVIPC_KABI_SLOT:-}"
else
  SLOT="${DROIDSPACES_SYSVIPC_KABI_SLOT:-6_7_8}"
  PATCH_DIR="$KERNEL_DIR/Droidspaces/Documentation/resources/kernel-patches/GKI/6.6/sysvipc_slot_${SLOT}"
fi

if [ -d "$PATCH_DIR" ]; then
  cd "$KERNEL_DIR/common"
  for p in "$PATCH_DIR"/*.patch; do
    [ -f "$p" ] && patch -p1 < "$p"
  done
fi

FRAGMENT="$KERNEL_DIR/common/CoreShift.fragment"
for opt in CONFIG_SYSVIPC CONFIG_POSIX_MQUEUE CONFIG_IPC_NS CONFIG_PID_NS CONFIG_DEVTMPFS CONFIG_TMPFS_XATTR; do
  grep -q "^$opt=y" "$FRAGMENT" 2>/dev/null || echo "$opt=y" >> "$FRAGMENT"
done
