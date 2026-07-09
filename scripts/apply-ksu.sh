#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:?kernel dir}"
VARIANT="${2:?ksu|kowsu|ksu-next}"

case "$VARIANT" in
  ksu)      REPO="https://github.com/tiann/KernelSU.git" ;;
  kowsu)    REPO="https://github.com/KOWX712/KernelSU.git" ;;
  ksu-next) REPO="${KSU_NEXT_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}" ;;
  *) echo "Unknown KSU variant: $VARIANT"; exit 1 ;;
esac

BRANCH="${KSU_CLONE_BRANCH:-${KSU_REF:-}}"

git clone --depth=1 ${BRANCH:+--branch "$BRANCH"} "$REPO" "$KERNEL_DIR/KernelSU"
git -C "$KERNEL_DIR/KernelSU" fetch --depth=1 origin --tags 2>/dev/null || true
cd "$KERNEL_DIR"
bash KernelSU/kernel/setup.sh ${KSU_CLONE_BRANCH:+$KSU_CLONE_BRANCH}
echo "CONFIG_KSU=y" >> "$KERNEL_DIR/common/CoreShift.fragment"
