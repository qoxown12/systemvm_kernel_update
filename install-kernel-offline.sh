#!/usr/bin/env bash
# This file is copied into the generated bundle as install-kernel.sh.
# check/check-boot do not install packages; install does not reboot; verify is post-reboot.
set -Eeuo pipefail
export LC_ALL=C
umask 022
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mode=${1:-check}
[[ $# -le 1 && ( $mode == check || $mode == install || $mode == verify || $mode == check-boot ) ]] ||
    die "Usage: sudo bash $0 check|install|check-boot|verify"
[[ $EUID -eq 0 ]] || die 'Run as root.'
source /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 12 ]] || die 'Requires Debian 12.'
[[ $(dpkg --print-architecture) == amd64 ]] || die 'Requires amd64.'
bundle_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $bundle_dir =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Extract into a path without spaces or special characters.'
cd "$bundle_dir"
sha256sum --strict -c SHA256SUMS > /dev/null || die 'Bundle integrity check failed.'
kernel_pkg=$(cat kernel-package.txt)
kernel_ver=$(cat kernel-version.txt)
meta_ver=$(cat meta-version.txt)
minimum=$(cat cve-fixed-version.txt)
[[ $kernel_pkg =~ ^linux-image-6\.1\.0-[0-9]+-amd64$ ]] || die 'Invalid kernel manifest.'
[[ $kernel_ver == "$meta_ver" && $kernel_ver =~ ^6\.1\.[0-9]+-[0-9A-Za-z.+~]+$ ]] || die 'Invalid version manifest.'
dpkg --compare-versions "$kernel_ver" ge "$minimum" || die 'Kernel is below the CVE fixed version.'
kernel_release=${kernel_pkg#linux-image-}
installed_version() {
    local info
    info=$(dpkg-query -W -f='${Status}\t${Version}' "$1" 2>/dev/null) || return 1
    [[ $info == 'install ok installed'* || $info == 'hold ok installed'* ]] || return 1
    printf '%s\n' "${info##*$'\t'}"
}
if [[ $mode == verify ]]; then
    [[ $(uname -r) == "$kernel_release" ]] || die "Running $(uname -r); expected $kernel_release."
    current=$(installed_version "$kernel_pkg") || die 'Target kernel package is not installed.'
    dpkg --compare-versions "$current" ge "$kernel_ver" || die 'Installed kernel package is too old.'
    # An ABI name can stay the same across security uploads. uname -r alone
    # cannot prove that the newly installed build is actually running.
    running_build=$(sed -n 's/.* Debian \([^ ]*\) .*/\1/p' /proc/version)
    [[ $running_build == "$current" ]] ||
        die "Running Debian build ${running_build:-unknown}; installed build $current. Reboot into the updated kernel."
    printf 'Verified: running %s, Debian build %s, CVE-2026-43499 fixed since %s.\n' "$kernel_release" "$current" "$minimum"
    printf 'Now validate SSVM/CPVM/VR functions and systemctl --failed.\n'
    exit 0
fi
audit=$(dpkg --audit)
[[ -z $audit ]] || die "Resolve existing dpkg problems first: $audit"
[[ -r $bundle_dir/kernel-boot-check.sh ]] || die 'Missing kernel-boot-check.sh; use a complete fixed bundle.'
source "$bundle_dir/kernel-boot-check.sh"
# Select the existing configuration; verify the running kernel after reboot.
grub_detect || die 'GRUB preflight failed. No packages installed.'
if [[ $mode == check-boot ]]; then
    current=$(installed_version "$kernel_pkg") || die 'Target kernel package is not installed.'
    dpkg --compare-versions "$current" ge "$kernel_ver" || die 'Installed target kernel is too old.'
    [[ -s /boot/vmlinuz-$kernel_release && -s /boot/initrd.img-$kernel_release && -d /lib/modules/$kernel_release ]] ||
        die 'Kernel/initramfs/modules missing. Do not reboot.'
    grub_validate_config_set "$grub_kind" "$grub_config" "$kernel_release"
    grub_show_selection "$grub_kind" "$grub_config"
    printf 'Boot entry check passed. No packages installed, no boot configuration changed, no reboot performed.\n'
    exit 0
fi
grub_require_update_tools "$grub_kind" "$grub_config" || die 'Required boot configuration tools/setup are unavailable. No packages installed.'
targets=("$kernel_pkg=$kernel_ver" "linux-image-amd64=$meta_ver")
while IFS= read -r root; do
    [[ $root =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || die 'Invalid root package manifest.'
    [[ $root == linux-image-amd64 ]] || targets+=("$root")
done < roots.txt
for name in "$kernel_pkg" linux-image-amd64; do
    if current=$(installed_version "$name"); then
        dpkg --compare-versions "$current" le "$kernel_ver" ||
            die "$name is newer ($current) than this bundle ($kernel_ver); refusing downgrade."
    fi
done
if command -v dkms >/dev/null; then
    dkms_state=$(dkms status) || die 'Cannot inspect DKMS state.'
    [[ -z $dkms_state ]] || die 'DKMS modules exist. Prepare matching headers/build dependencies and a separately validated bundle.'
fi
runtime_dir=$(mktemp -d "${TMPDIR:-/var/tmp}/kernel-offline.XXXXXXXX")
chmod 0755 "$runtime_dir"
cleanup() {
    rc=$?
    if [[ $rc -eq 0 ]]; then
        rm -rf -- "$runtime_dir"
    else
        printf 'Diagnostic APT files retained: %s\n' "$runtime_dir" >&2
    fi
}
trap cleanup EXIT
mkdir -p "$runtime_dir/lists/partial" "$runtime_dir/archives/partial" "$runtime_dir/empty.d" "$runtime_dir/log"
touch "$runtime_dir/empty.conf"
printf 'deb [trusted=yes] file:%s/repo ./\n' "$bundle_dir" > "$runtime_dir/sources.list"
cat > "$runtime_dir/apt.conf" <<CONFIG
Dir::Etc::parts "$runtime_dir/empty.d";
Dir::Etc::main "$runtime_dir/empty.conf";
Dir::Etc::sourcelist "$runtime_dir/sources.list";
Dir::Etc::sourceparts "$runtime_dir/empty.d";
Dir::State::status "/var/lib/dpkg/status";
Dir::State::lists "$runtime_dir/lists";
Dir::Cache::archives "$runtime_dir/archives";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
Dir::Log "$runtime_dir/log";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::allow-Downgrades "false";
APT::Get::allow-Change-Held-Packages "false";
Acquire::Languages "none";
CONFIG
# Installed state, holds and target preferences are retained. Host apt.conf
# hooks and network sources are disabled. Debian package maintainer scripts and
# /etc/kernel hooks will still run during installation.
local_apt() { APT_CONFIG="$runtime_dir/apt.conf" /usr/bin/apt-get "$@"; }
printf 'Running kernel: %s\nTarget: %s=%s\n' "$(uname -r)" "$kernel_pkg" "$kernel_ver"
local_apt -o APT::Update::Error-Mode=any update > "$runtime_dir/update.log" 2>&1 || {
    cat "$runtime_dir/update.log" >&2; die 'Local repository update failed.';
}
local_apt --simulate --no-remove --no-install-recommends install "${targets[@]}" > "$runtime_dir/plan.txt" 2>&1 || {
    cat "$runtime_dir/plan.txt" >&2; die 'Dependency simulation failed. Do not install.';
}
cat "$runtime_dir/plan.txt"
holds=$(apt-mark showhold)
while read -r action name rest; do
    [[ $action == Inst ]] || continue
    name=${name%:amd64}
    if grep -Fxq -- "$name" <<< "$holds"; then
        die "Planned change to held package $name. Resolve the hold explicitly before retrying."
    fi
done < "$runtime_dir/plan.txt"
# Link the authenticated bundle bytes into a private cache where possible.
# file: APT sources do not necessarily populate archives with --download-only.
for deb in "$bundle_dir"/repo/*.deb; do
    ln -- "$deb" "$runtime_dir/archives/${deb##*/}" 2>/dev/null || cp -- "$deb" "$runtime_dir/archives/"
done
local_apt --yes --download-only --no-remove --no-install-recommends install "${targets[@]}" || die 'Local package prefetch failed.'
printf '\nLocal dependency and package integrity checks passed.\n'
if grep -q "^Inst $kernel_pkg " "$runtime_dir/plan.txt"; then
    kernel_kib=$(awk -F '\t' -v p="$kernel_pkg" '$1==p {print $5}' packages.tsv)
    module_free=$(df -Pk /lib/modules | awk 'END {print $4}')
    boot_free=$(df -Pk /boot | awk 'END {print $4}')
    # Conservative allowance: modules plus 128 MiB for kernel/initramfs.
    [[ $kernel_kib =~ ^[0-9]+$ ]] || die 'Missing kernel size estimate.'
    if [[ $(stat -c %d /boot) == "$(stat -c %d /lib/modules)" ]]; then
        (( module_free >= kernel_kib + 131072 )) || die 'Insufficient space for modules and initramfs.'
    else
        (( module_free >= kernel_kib )) || die 'Insufficient space on the module filesystem.'
        (( boot_free >= 131072 )) || die 'Less than 128 MiB free on /boot.'
    fi
fi
mkdir -p "$bundle_dir/logs"
log_tag="$(date -u +%Y%m%dT%H%M%SZ)-$$-$mode"
cp "$runtime_dir/plan.txt" "$bundle_dir/logs/$log_tag-plan.txt"
printf 'Preflight passed. Plan: %s/logs/%s-plan.txt\n' "$bundle_dir" "$log_tag"
if [[ $mode == check ]]; then
    printf 'No packages installed. Validate install/reboot on a matching clone before fleet rollout.\n'
    exit 0
fi
printf '\nInstalling pinned kernel; package removal and reboot are disabled.\n'
local_apt --yes --no-download --no-remove --no-install-recommends install "${targets[@]}" 2>&1 |
    tee "$bundle_dir/logs/$log_tag-install.txt"
audit=$(dpkg --audit)
[[ -z $audit ]] || die "Post-install audit failed: $audit"
[[ $(installed_version "$kernel_pkg") == "$kernel_ver" ]] || die 'Kernel package version check failed.'
update-initramfs -u -k "$kernel_release"
[[ -s /boot/vmlinuz-$kernel_release && -s /boot/initrd.img-$kernel_release && -d /lib/modules/$kernel_release ]] ||
    die 'Missing kernel/initramfs/modules. Do not reboot.'
grub_update_config_set "$grub_kind" "$grub_config" "$kernel_release"
grub_show_selection "$grub_kind" "$grub_config"
printf '\nInstalled %s. No reboot performed.\n' "$kernel_release"
printf 'Check GRUB default/saved entry and recovery console, reboot in maintenance, then run:\n'
printf 'sudo bash %s/install-kernel.sh verify\n' "$bundle_dir"
