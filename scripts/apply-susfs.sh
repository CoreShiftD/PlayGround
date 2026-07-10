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
git clone ${SUSFS_REF_RESOLVED:+--branch "$SUSFS_REF_RESOLVED"} "$SUSFS_REPO" "$SUSFS_DIR"
git -C "$SUSFS_DIR" fetch origin --tags 2>/dev/null || true

[ -f "$SUSFS_DIR/kernel_patches/fs/susfs.c" ] && cp "$SUSFS_DIR/kernel_patches/fs/susfs.c" "$COMMON_DIR/fs/"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" ] && cp "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" "$COMMON_DIR/include/linux/"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" ] && cp "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$COMMON_DIR/include/linux/"

ROOT="$(dirname "$(readlink -f "$0")")/.."
LOCAL_OVERRIDE_DIR="$ROOT/patches/susfs/$PROFILE"

cd "$COMMON_DIR"
for p in "$SUSFS_DIR"/kernel_patches/50_add_susfs_in_*.patch; do
  [ -f "$p" ] || continue

  # Fix context line: kernel renamed vma_pages -> vma_data_pages
  # on android16-6.12+ but SUSFS patches still reference vma_pages.
  case "$PROFILE" in *6.12*) sed -i 's/\bvma_pages\b/vma_data_pages/g' "$p" ;; esac

  # Check for local override patches (per-version file-specific .patch files
  # that replace sections of the SUSFS patch where context has drifted).
  declare -a overrides=()
  while IFS= read -r -d '' f; do overrides+=("$f"); done < \
    <(find "$LOCAL_OVERRIDE_DIR" -name '*.patch' -type f -print0 2>/dev/null || true)

  if [ "${#overrides[@]}" -gt 0 ]; then
    # Strip overridden file sections from the SUSFS patch
    cp "$p" "${p}.stripped"
    for override in "${overrides[@]}"; do
      target_file=$(head -1 "$override" | sed -n 's/^--- a\/\(.*\)/\1/p')
      [ -n "$target_file" ] || continue
      sed -i "\|^diff --git a/$target_file|,\|^diff --git |{\|^diff --git a/$target_file|d;\|^diff --git |!d}" "${p}.stripped"
    done
    patch --fuzz=3 -p1 < "${p}.stripped" || true
    rm -f "${p}.stripped"
    for override in "${overrides[@]}"; do
      patch --fuzz=3 -p1 < "$override" || true
    done
  else
    patch --fuzz=3 -p1 < "$p" || true
  fi
done

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