#!/usr/bin/env bash
# Apply this small, checksummed metadata patch to an existing kernel bundle.
# No package installation, update-grub, initramfs generation or reboot occurs.
set -Eeuo pipefail
export LC_ALL=C
umask 022
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || die "Usage: bash $0 EXTRACTED-KERNEL-BUNDLE-DIRECTORY"
[[ $EUID -eq 0 ]] || die 'Run as root.'
patch_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
target=$(cd -- "$1" && pwd -P)
[[ $target =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Use a bundle path without spaces or special characters.'
[[ -f $patch_dir/SHA256SUMS && -d $patch_dir/payload ]] || die 'Extract the complete fix archive first.'
(cd "$patch_dir" && sha256sum --strict -c SHA256SUMS > /dev/null) || die 'Fix archive integrity check failed.'
[[ -f $target/SHA256SUMS && -f $target/kernel-package.txt && -f $target/kernel-version.txt ]] || die 'Not a kernel bundle.'
[[ $(cat "$target/kernel-package.txt") =~ ^linux-image-6\.1\.0-[0-9]+-amd64$ ]] || die 'Unexpected kernel manifest.'
# Verify all existing protected files before replacing any metadata. Do not
# regenerate checksums of unverified package files to silence integrity errors.
(cd "$target" && sha256sum --strict -c SHA256SUMS > /dev/null) || die 'Existing bundle integrity check failed; restore a verified bundle first.'
files=(install-kernel.sh kernel-boot-check.sh README-KO.txt
       source/prepare-debian12-kernel-offline.sh source/install-kernel-offline.sh
       source/kernel-boot-check.sh source/README-KO.txt GRUB오류조치.md)
for file in "${files[@]}"; do
    [[ -f $patch_dir/payload/$file ]] || die "Fix payload missing $file"
done
backup=$(mktemp -d "$target/.grubfix-backup.XXXXXXXX")
cp -- "$target/SHA256SUMS" "$backup/SHA256SUMS"
for file in "${files[@]}"; do
    if [[ -e $target/$file ]]; then
        mkdir -p -- "$backup/$(dirname -- "$file")"
        cp -p -- "$target/$file" "$backup/$file"
    fi
done
trap 'rc=$?; printf "Fix interrupted. Original metadata retained in %s (exit %s).\n" "$backup" "$rc" >&2; exit "$rc"' ERR
printf './%s\n' "${files[@]}" > "$backup/replaced-paths.txt"
awk 'NR==FNR {changed[$0]=1; next} !($2 in changed)' \
    "$backup/replaced-paths.txt" "$target/SHA256SUMS" > "$backup/new-SHA256SUMS"
for file in "${files[@]}"; do
    mkdir -p -- "$target/$(dirname -- "$file")"
    cp -- "$patch_dir/payload/$file" "$target/$file"
    if [[ $file == *.sh ]]; then chmod 0755 "$target/$file"; fi
    (cd "$target" && sha256sum "./$file") >> "$backup/new-SHA256SUMS"
done
cp -- "$backup/new-SHA256SUMS" "$target/SHA256SUMS"
(cd "$target" && sha256sum --strict -c SHA256SUMS > /dev/null)
printf 'GRUB check fix applied. Original metadata: %s\n' "$backup"
printf 'No packages installed, no boot files changed, no reboot performed.\n'
printf 'For the already installed target kernel, run from the bundle directory:\n'
printf 'bash install-kernel.sh check-boot\n'
