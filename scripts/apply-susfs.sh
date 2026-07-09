#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="${1:?workspace dir}"
PROFILE="${2:?androidXX-X.XX}"

COMMON_DIR="$WORKSPACE_DIR/common"
FRAGMENT="$COMMON_DIR/CoreShift.fragment"
FEATURES_LST="$COMMON_DIR/features.lst"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_DIR="$COMMON_DIR/SUSFS"

ANDROID_KERNEL="${PROFILE}"

is_ksu_next=false
[ -f "$FEATURES_LST" ] && grep -qw "ksu-next" "$FEATURES_LST" && is_ksu_next=true

resolve_ref() {
  if [ -n "${SUSFS_REF:-}" ]; then echo "$SUSFS_REF"; return; fi
  local c
  for c in "gki-${ANDROID_KERNEL}-dev" "gki-${ANDROID_KERNEL}"; do
    git ls-remote --heads "$SUSFS_REPO" "$c" 2>/dev/null | grep -q . && { echo "$c"; return; }
  done
  echo ""
}

SUSFS_REF_RESOLVED="$(resolve_ref)"
git clone --depth=1 ${SUSFS_REF_RESOLVED:+--branch "$SUSFS_REF_RESOLVED"} "$SUSFS_REPO" "$SUSFS_DIR"

# Copy source files
[ -f "$SUSFS_DIR/kernel_patches/fs/susfs.c" ] && cp "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$COMMON_DIR/fs/"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" ] && cp "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" "$COMMON_DIR/include/linux/"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" ] && cp "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$COMMON_DIR/include/linux/"

# Apply the per-branch patch (50_add_susfs_in_gki-*.patch)
cd "$COMMON_DIR"
for p in "$SUSFS_DIR"/kernel_patches/50_add_susfs_in_*.patch; do
  [ -f "$p" ] && patch --fuzz=3 -p1 < "$p"
done

# Apply KSU SUSFS integration patch (skip for ksu-next)
if ! $is_ksu_next; then
  KSU_PATCH="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  [ -f "$KSU_PATCH" ] && patch --fuzz=3 -p1 < "$KSU_PATCH"
fi

# Discover SUSFS Kconfig symbols
SUSFS_SYMBOLS=""
[ -f "$SUSFS_DIR/Kconfig" ] && SUSFS_SYMBOLS=$(grep -oP 'config\s+\K\w+' "$SUSFS_DIR/Kconfig" | grep SUSFS || true)
[ -z "$SUSFS_SYMBOLS" ] && SUSFS_SYMBOLS="KSU_SUSFS"

for sym in $SUSFS_SYMBOLS; do
  grep -qxF "CONFIG_${sym}=y" "$FRAGMENT" 2>/dev/null || echo "CONFIG_${sym}=y" >> "$FRAGMENT"
done