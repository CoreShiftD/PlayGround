#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="${1:?workspace dir}"
PROFILE="${2:?androidXX-X.XX}"

COMMON_DIR="$WORKSPACE_DIR/common"
FRAGMENT="$COMMON_DIR/CoreShift.fragment"
FEATURES_LST="$COMMON_DIR/features.lst"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_DIR="$COMMON_DIR/SUSFS"

is_ksu_next=false
[ -f "$FEATURES_LST" ] && grep -qw "ksu-next" "$FEATURES_LST" && is_ksu_next=true

resolve_ref() {
  if [ -n "${SUSFS_REF:-}" ]; then echo "$SUSFS_REF"; return; fi
  local c
  for c in "gki-${PROFILE}-dev" "gki-${PROFILE}"; do
    git ls-remote --heads "$SUSFS_REPO" "$c" 2>/dev/null | grep -q . && { echo "$c"; return; }
  done
  echo ""
}

SUSFS_REF_RESOLVED="$(resolve_ref)"
git clone --depth=1 ${SUSFS_REF_RESOLVED:+--branch "$SUSFS_REF_RESOLVED"} "$SUSFS_REPO" "$SUSFS_DIR"

[ -f "$SUSFS_DIR/kernel_patches/fs/susfs.c" ] && cp "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$COMMON_DIR/fs/"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" ] && cp "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" "$COMMON_DIR/include/linux/"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" ] && cp "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$COMMON_DIR/include/linux/"

cd "$COMMON_DIR"
for p in "$SUSFS_DIR"/kernel_patches/50_add_susfs_in_*.patch; do
  [ -f "$p" ] || continue
  if grep -q '^diff --git a/fs/namespace.c' "$p"; then
    sed '/^diff --git a\/fs\/namespace.c/,/^diff --git /{/^diff --git a\/fs\/namespace.c/d;/^diff --git /!d}' "$p" > "${p}.stripped"
    patch --fuzz=3 -p1 < "${p}.stripped"
    rm -f "${p}.stripped"
  else
    patch --fuzz=3 -p1 < "$p"
  fi
done

if ! grep -q 'susfs_def.h' "fs/namespace.c" 2>/dev/null; then
  if grep -qF '#include <linux/mnt_idmapping.h>' "fs/namespace.c" 2>/dev/null; then
    sed -i '\|#include <linux/mnt_idmapping.h>|a\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif\n\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nextern bool susfs_is_current_ksu_domain(void);\nextern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n#define CL_COPY_MNT_NS BIT(25)\n#endif' "fs/namespace.c"
  fi
fi

find . -name '*.rej' -delete 2>/dev/null || true

if ! $is_ksu_next; then
  KSU_PATCH="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
  if [ -f "$KSU_PATCH" ]; then
    cd "$WORKSPACE_DIR/KernelSU"
    patch --fuzz=3 -p1 < "$KSU_PATCH"
    cd "$COMMON_DIR"
  fi
fi

# Scan kernel tree for KSU_SUSFS Kconfig symbols declared by the applied patches
SUSFS_SYMBOLS=$(find "$COMMON_DIR" -type f \( -name 'Kconfig' -o -name 'Kconfig.*' \) \
  -exec grep -hE '^[[:space:]]*config[[:space:]]+KSU_SUSFS[A-Z0-9_]*' {} + 2>/dev/null \
  | sed -E 's/^[[:space:]]*config[[:space:]]+//' | sort -u || true)

if [ -z "$SUSFS_SYMBOLS" ]; then
  SUSFS_SYMBOLS="KSU_SUSFS"
fi

for sym in $SUSFS_SYMBOLS; do
  grep -qxF "CONFIG_${sym}=y" "$FRAGMENT" 2>/dev/null || echo "CONFIG_${sym}=y" >> "$FRAGMENT"
done