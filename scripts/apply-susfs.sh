#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:?kernel dir}"
PROFILE="${2:?androidXX-X.XX}"

REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
REF="${SUSFS_REF:-}"
KSU_VARIANT="${KSU_VARIANT:-}"

git clone --depth=1 ${REF:+--branch "$REF"} "$REPO" "$KERNEL_DIR/SUSFS"

cp "$KERNEL_DIR/SUSFS/fs/susfs.c" "$KERNEL_DIR/common/fs/" 2>/dev/null || true
cp "$KERNEL_DIR/SUSFS/fs/susfs_utils.c" "$KERNEL_DIR/common/fs/" 2>/dev/null || true
cp "$KERNEL_DIR/SUSFS/include/linux/susfs.h" "$KERNEL_DIR/common/include/linux/" 2>/dev/null || true
cp "$KERNEL_DIR/SUSFS/include/linux/susfs_def.h" "$KERNEL_DIR/common/include/linux/" 2>/dev/null || true

PATCH_DIR=""
for candidate in \
  "$KERNEL_DIR/SUSFS/kernel_patches/$PROFILE" \
  "$KERNEL_DIR/SUSFS/kernel_patches/android-${PROFILE#android}" \
  "$(echo "$KERNEL_DIR/SUSFS/kernel_patches"/*"${PROFILE##*-}"* 2>/dev/null || true)" \
  "$KERNEL_DIR/SUSFS/patches/$PROFILE"; do
  if [ -d "$candidate" ]; then
    PATCH_DIR="$candidate"
    break
  fi
done

if [ -n "$PATCH_DIR" ]; then
  cd "$KERNEL_DIR/common"
  for p in "$PATCH_DIR"/*.patch; do
    [ -f "$p" ] && patch --fuzz=3 -p1 < "$p"
  done
fi

if [ "$KSU_VARIANT" != "ksu-next" ]; then
  KSU_PATCH="$KERNEL_DIR/SUSFS/kernel_patches/10_enable_susfs_for_ksu.patch"
  [ -f "$KSU_PATCH" ] && patch -d "$KERNEL_DIR/common" --fuzz=3 -p1 < "$KSU_PATCH"
fi

FRAGMENT="$KERNEL_DIR/common/CoreShift.fragment"
for sym in KSU_SUSFS_PATH KSU_SUSFS_SUS_SU KSU_SUSFS_SUS_MOUNT KSU_SUSFS_AUTO_ADD_GID KSU_SUSFS_SUS_KILL KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MOUNT_MARK; do
  grep -q "$sym" "$FRAGMENT" 2>/dev/null || echo "CONFIG_${sym}=y" >> "$FRAGMENT"
done
