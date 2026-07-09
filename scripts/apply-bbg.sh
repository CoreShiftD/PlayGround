#!/usr/bin/env bash
set -euo pipefail

KERNEL_DIR="${1:?kernel dir}"

REPO="${BBG_REPO:-https://github.com/vc-teahouse/Baseband-guard.git}"
REF="${BBG_REF:-}"

git clone --depth=1 ${REF:+--branch "$REF"} "$REPO" "$KERNEL_DIR/Baseband-guard"
cd "$KERNEL_DIR"
sh Baseband-guard/setup.sh
echo "CONFIG_BBG=y" >> "$KERNEL_DIR/common/CoreShift.fragment"

FRAGMENT="$KERNEL_DIR/common/CoreShift.fragment"
if grep -q 'CONFIG_DEFAULT_SECURITY_SMACK=y' "$KERNEL_DIR/common/arch/arm64/configs/gki_defconfig"; then
  echo 'CONFIG_LSM="lockdown,yama,loadpin,safesetid,integrity,smack,selinux,tomoyo,apparmor,bpf,baseband_guard"' >> "$FRAGMENT"
elif grep -q 'CONFIG_DEFAULT_SECURITY_APPARMOR=y' "$KERNEL_DIR/common/arch/arm64/configs/gki_defconfig"; then
  echo 'CONFIG_LSM="lockdown,yama,loadpin,safesetid,integrity,apparmor,selinux,smack,tomoyo,bpf,baseband_guard"' >> "$FRAGMENT"
elif grep -q 'CONFIG_DEFAULT_SECURITY_TOMOYO=y' "$KERNEL_DIR/common/arch/arm64/configs/gki_defconfig"; then
  echo 'CONFIG_LSM="lockdown,yama,loadpin,safesetid,integrity,tomoyo,bpf,baseband_guard"' >> "$FRAGMENT"
elif grep -q 'CONFIG_DEFAULT_SECURITY_DAC=y' "$KERNEL_DIR/common/arch/arm64/configs/gki_defconfig"; then
  echo 'CONFIG_LSM="lockdown,yama,loadpin,safesetid,integrity,bpf,baseband_guard"' >> "$FRAGMENT"
else
  echo 'CONFIG_LSM="lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf,baseband_guard"' >> "$FRAGMENT"
fi
