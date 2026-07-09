#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="${1:?workspace dir}"
PROFILE="${2:?androidXX-X.XX}"

COMMON_DIR="$WORKSPACE_DIR/common"
FRAGMENT="$COMMON_DIR/CoreShift.fragment"
FEATURES_LST="$COMMON_DIR/features.lst"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_DIR="$COMMON_DIR/SUSFS"

ANDROID_RELEASE="${PROFILE%-*}"
KERNEL_VERSION="${PROFILE#*-}"

is_ksu_next=false
if [ -f "$FEATURES_LST" ] && grep -qw "ksu-next" "$FEATURES_LST"; then
  is_ksu_next=true
fi

# Resolve SUSFS ref
resolve_ref() {
  if [ -n "${SUSFS_REF:-}" ]; then
    echo "$SUSFS_REF"
    return
  fi
  local candidate
  for candidate in \
    "gki-$ANDROID_RELEASE-$KERNEL_VERSION-dev" \
    "gki-$ANDROID_RELEASE-$KERNEL_VERSION" \
    "gki-android$ANDROID_RELEASE-$KERNEL_VERSION-dev"; do
    if git ls-remote --heads "$SUSFS_REPO" "$candidate" 2>/dev/null | grep -q .; then
      echo "$candidate"
      return
    fi
  done
  echo ""
}

SUSFS_REF_RESOLVED="$(resolve_ref)"

git clone --depth=1 ${SUSFS_REF_RESOLVED:+--branch "$SUSFS_REF_RESOLVED"} "$SUSFS_REPO" "$SUSFS_DIR"

# Copy source files
cp "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$COMMON_DIR/fs/" 2>/dev/null || true
cp "$SUSFS_DIR/kernel_patches/fs/susfs_utils.c" "$COMMON_DIR/fs/" 2>/dev/null || true
cp "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" "$COMMON_DIR/include/linux/" 2>/dev/null || true
cp "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$COMMON_DIR/include/linux/" 2>/dev/null || true

# Apply kernel patches
PATCH_DIR=""
for candidate in \
  "$SUSFS_DIR/kernel_patches/$PROFILE" \
  "$SUSFS_DIR/kernel_patches/android-$KERNEL_VERSION" \
  "$SUSFS_DIR/patches/$PROFILE"; do
  if [ -d "$candidate" ]; then
    PATCH_DIR="$candidate"
    break
  fi
done

if [ -n "$PATCH_DIR" ]; then
  cd "$COMMON_DIR"
  for p in "$PATCH_DIR"/*.patch; do
    [ -f "$p" ] && patch --fuzz=3 -p1 < "$p"
  done
fi

# Apply the 50_add_susfs_in_kernel patch for legacy kernels
LEGACY_PATCH="$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-$KERNEL_VERSION.patch"
if [ -f "$LEGACY_PATCH" ]; then
  cd "$COMMON_DIR" && patch --fuzz=3 -p1 < "$LEGACY_PATCH"
fi

# Apply KSU SUSFS integration patch (skip for ksu-next)
if ! $is_ksu_next; then
  KSU_PATCH="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  if [ -f "$KSU_PATCH" ]; then
    cd "$COMMON_DIR" && patch --fuzz=3 -p1 < "$KSU_PATCH"
  fi
fi

# Discover SUSFS Kconfig symbols from the source
SUSFS_CONFIG_SYMBOLS=""
if [ -f "$SUSFS_DIR/Kconfig" ]; then
  SUSFS_CONFIG_SYMBOLS=$(grep -oP 'config\s+\K\w+' "$SUSFS_DIR/Kconfig" | grep SUSFS || true)
fi

if [ -z "$SUSFS_CONFIG_SYMBOLS" ]; then
  SUSFS_CONFIG_SYMBOLS="KSU_SUSFS"
fi

# Write configs to fragment
ensure_line_once() {
  local line="$1"
  grep -qxF "$line" "$FRAGMENT" 2>/dev/null || echo "$line" >> "$FRAGMENT"
}

ensure_line_once "CONFIG_KSU=y"
for sym in $SUSFS_CONFIG_SYMBOLS; do
  ensure_line_once "CONFIG_${sym}=y"
done