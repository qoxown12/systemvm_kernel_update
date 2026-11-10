#!/usr/bin/env bash
# Run on each representative OFFLINE Debian 12 amd64 SystemVM. No apt update.
set -Eeuo pipefail
export LC_ALL=C
umask 077
if [[ ${1:-} == --help ]]; then
    printf 'Usage: sudo bash %s [new-output-directory]\n' "$0"
    exit 0
fi
[[ $EUID -eq 0 && $# -le 1 ]] || { echo 'Run as root with at most one output directory.' >&2; exit 1; }
source /etc/os-release
[[ $ID == debian && $VERSION_ID == 12 && $(dpkg --print-architecture) == amd64 ]] || {
    echo 'Requires Debian 12 amd64.' >&2; exit 1;
}
dest=${1:-./systemvm-state-$(hostname)-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -- "$dest"
cp /var/lib/dpkg/status "$dest/status"
cp /etc/os-release "$dest/os-release"
{
    date -u +%FT%TZ
    uname -r
    dpkg --print-architecture
    printf '\nPackage audit:\n'
    dpkg --audit
    printf '\nHolds:\n'
    apt-mark showhold
    printf '\nFilesystems:\n'
    df -h / /boot /lib/modules
    printf '\nBoot files:\n'
    ls -lh /boot
    printf '\nRelevant installed packages:\n'
    dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' 'linux-image*' 'initramfs*' 'grub*' 'dkms' 2>/dev/null || true
} > "$dest/report.txt"
(cd "$dest" && sha256sum status os-release report.txt > SHA256SUMS)
printf 'Collected: %s\nReturn its status file to the downloader with --target-status.\n' "$dest"
