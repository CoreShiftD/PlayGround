#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="${1:?workspace dir (where common/ lives)}"
VARIANT="${2:?variant name}"
PROFILE="${3:?profile name (androidXX-X.XX)}"

ROOT="$(dirname "$(readlink -f "$0")")/.."
VARIANT_PATH="$ROOT/variants.json"

FEATURES=$(python3 -c "
import json, sys
with open('$VARIANT_PATH') as f:
    data = json.load(f)
v = data['variants'].get('$VARIANT')
if v is None:
    sys.exit(1)
print(','.join(v['features']), end='')
") || { echo "Unknown variant: $VARIANT" >&2; exit 1; }

echo "Applying variant $VARIANT -> features: ${FEATURES:-none}"
echo "$FEATURES" > "$WORKSPACE_DIR/common/features.lst"

: > "$WORKSPACE_DIR/common/CoreShift.fragment"

[ -z "$FEATURES" ] && exit 0

IFS=',' read -ra F <<< "$FEATURES"
for feat in "${F[@]}"; do
  case "$feat" in
    ksu)      "$ROOT/scripts/apply-ksu.sh" "$WORKSPACE_DIR" "ksu" ;;
    kowsu)    "$ROOT/scripts/apply-ksu.sh" "$WORKSPACE_DIR" "kowsu" ;;
    ksu-next)
      HAS_SUSFS=false
      for f2 in "${F[@]}"; do [ "$f2" = "susfs" ] && HAS_SUSFS=true; done
      if $HAS_SUSFS; then
        KSU_CLONE_BRANCH=dev-susfs KSU_REF=dev-susfs \
          "$ROOT/scripts/apply-ksu.sh" "$WORKSPACE_DIR" "ksu-next"
      else
        "$ROOT/scripts/apply-ksu.sh" "$WORKSPACE_DIR" "ksu-next"
      fi
      ;;
    susfs)
      KSU_VARIANT=""
      KSU_NEXT_HAS_SUSFS=false
      for f2 in "${F[@]}"; do
        [ "$f2" = "ksu-next" ] && KSU_NEXT_HAS_SUSFS=true
      done
      if $KSU_NEXT_HAS_SUSFS; then
        echo "SUSFS already integrated via KernelSU-Next dev-susfs branch, skipping apply-susfs.sh"
        continue
      fi
      KSU_VARIANT="$KSU_VARIANT" "$ROOT/scripts/apply-susfs.sh" "$WORKSPACE_DIR" "$PROFILE"
      ;;
    droidspaces) "$ROOT/scripts/apply-droidspaces.sh" "$WORKSPACE_DIR" ;;
    *) echo "Unknown feature: $feat"; exit 1 ;;
  esac
done
