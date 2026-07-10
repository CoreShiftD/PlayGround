#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${1:?profile name (androidXX-X.XX)}"
WORKSPACE_DIR="${2:?workspace dir}"
ARTIFACT_DIR="${3:?artifact dir}"
AK3_REF="${AK3_REF:-master}"
AK3_DIR="$WORKSPACE_DIR/.packaging/AnyKernel3"
AK3_REPO_URL="https://github.com/osm0sis/AnyKernel3"

for tool in git zip unzip strings; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing: $tool" >&2; exit 1; }
done

COMMON_DIR="$WORKSPACE_DIR/common"
mkdir -p "$ARTIFACT_DIR"

find_first_named() {
  local name="$1"
  shift
  for root in "$@"; do
    [ -d "$root" ] || continue
    found="$(find "$root" -type f -name "$name" 2>/dev/null | sort | head -n1)"
    [ -n "$found" ] && { echo "$found"; return 0; }
  done
  return 1
}

select_final_config() {
  local candidates=()
  while IFS= read -r c; do candidates+=("$c"); done < <(
    find "$ARTIFACT_DIR" "$WORKSPACE_DIR/out" "$COMMON_DIR/out" "$WORKSPACE_DIR/dist" \
      -type f -name '.config' 2>/dev/null | sort
  )
  local best=""
  local best_rank=99 rank
  for candidate in "${candidates[@]}"; do
    rank=3
    case "$candidate" in *workspace-out*) rank=0;; *common-out*) rank=1;; *workspace-dist*) rank=2;; esac
    if [ -z "$best" ] || [ "$rank" -lt "$best_rank" ] || { [ "$rank" -eq "$best_rank" ] && [[ "$candidate" < "$best" ]]; }; then
      best="$candidate"; best_rank="$rank"
    fi
  done
  [ -n "$best" ] && echo "$best" || return 1
}

RAW_IMAGE_PATH="$(find_first_named "Image" "$ARTIFACT_DIR" "$WORKSPACE_DIR/dist" "$WORKSPACE_DIR/out" "$COMMON_DIR/out" || true)"
if [ -z "$RAW_IMAGE_PATH" ]; then
  echo "No Image found" >&2; exit 1
fi

FINAL_CONFIG_PATH="$(select_final_config || true)"
if [ -z "$FINAL_CONFIG_PATH" ]; then
  echo "No .config found" >&2; exit 1
fi

if [ -d "$AK3_DIR" ]; then
  rm -rf "$AK3_DIR"
fi
git clone --depth=1 -b "$AK3_REF" "$AK3_REPO_URL" "$AK3_DIR"

if [ ! -f "$AK3_DIR/anykernel.sh" ] || [ ! -d "$AK3_DIR/tools" ]; then
  echo "AnyKernel3 clone broken" >&2; exit 1
fi

chmod +x "$AK3_DIR/anykernel.sh"
chmod +x "$AK3_DIR/tools/"* 2>/dev/null || true

cp -f "$RAW_IMAGE_PATH" "$AK3_DIR/Image"
cp -f "$FINAL_CONFIG_PATH" "$AK3_DIR/ikconfig.txt"
cp -f "$FINAL_CONFIG_PATH" "$ARTIFACT_DIR/ikconfig.txt"

kernel_version="$(strings "$AK3_DIR/Image" 2>/dev/null | grep -E -m1 'Linux version [0-9]+\.[0-9]+' | awk '{print $3}' || true)"
[ -z "$kernel_version" ] && kernel_version="$PROFILE_NAME"
kernel_version="$(printf '%s' "$kernel_version" | sed 's/-maybe-dirty//g; s/-dirty//g; s/-[0-9]\{1,\}-g[0-9a-f]\{7,\}//g; s/-[0-9]\{1,\}k//g')"

sanitized_kernel_version="$(
  printf '%s' "$kernel_version" | tr ' /' '--' | sed 's/[^A-Za-z0-9._+-]/-/g; s/--*/-/g; s/^-//; s/-$//'
)"
[ -z "$sanitized_kernel_version" ] && sanitized_kernel_version="$PROFILE_NAME"

suffixes=("CoreShift")
if [ -n "${CORESHIFT_AK3_SUFFIXES:-}" ]; then
  IFS=',' read -r -a extra_suffixes <<< "${CORESHIFT_AK3_SUFFIXES}"
  for suffix in "${extra_suffixes[@]}"; do
    suffix="$(printf '%s' "$suffix" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[^A-Za-z0-9._+-]/-/g; s/--*/-/g; s/^-//; s/-$//')"
    [ -n "$suffix" ] || continue
    suffixes+=("$suffix")
  done
fi

suffix_string="$(IFS=-; printf '%s' "${suffixes[*]}")"
ZIP_PATH="$ARTIFACT_DIR/${sanitized_kernel_version}-${suffix_string}.zip"

rm -f "$ZIP_PATH"
(cd "$AK3_DIR" && zip -r9 "$ZIP_PATH" . -x ".git/*" ".github/*" "README.md")

echo "Packaged: $ZIP_PATH"
unzip -l "$ZIP_PATH" | sed -n '1,160p'