#!/usr/bin/env bash
# Installed at the ISO root as install-kernel.sh. No writes to the ISO.
# Prepare a verified local copy, then run the existing kernel installer.
set -Eeuo pipefail
export LC_ALL=C
umask 022
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mode=${1:-check}
if [[ $mode == --help || $mode == -h ]]; then
    printf 'Usage: sudo bash %s check|install|check-boot|verify\n' "$0"
    printf 'Cache: /var/lib/systemvm-kernel-offline (override: KERNEL_OFFLINE_CACHE_DIR)\n'
    exit 0
fi
[[ $# -le 1 && ( $mode == check || $mode == install || $mode == check-boot || $mode == verify ) ]] ||
    die "Usage: sudo bash $0 check|install|check-boot|verify"
[[ $EUID -eq 0 ]] || die 'Run as root.'
for cmd in sha256sum tar flock realpath stat cmp; do
    command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
media_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $media_dir =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Use a simple mount path without spaces.'
(cd "$media_dir" && sha256sum --strict -c SHA256SUMS > /dev/null) || die 'ISO content integrity check failed.'
bundle_name=$(cat "$media_dir/bundle-name.txt")
payload_file=$(cat "$media_dir/payload-file.txt")
payload_digest=$(cat "$media_dir/payload-sha256.txt")
[[ $bundle_name =~ ^debian12-kernel-amd64-[A-Za-z0-9_.-]+$ ]] || die 'Invalid ISO bundle metadata.'
[[ $payload_file == "$bundle_name.tar.gz" && $payload_digest =~ ^[0-9a-f]{64}$ ]] || die 'Invalid payload metadata.'
manifest_payload_digest=$(awk -v path="./payload/$payload_file" '$2==path {print $1}' "$media_dir/SHA256SUMS")
[[ $manifest_payload_digest == "$payload_digest" ]] || die 'Payload digest metadata does not match the ISO manifest.'
cache_root=${KERNEL_OFFLINE_CACHE_DIR:-/var/lib/systemvm-kernel-offline}
[[ $cache_root =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Use a simple absolute cache path.'
mkdir -p -- "$cache_root"
cache_root=$(realpath -- "$cache_root")
[[ $(stat -c %u "$cache_root") == 0 ]] || die 'Cache directory must be owned by root.'
cache_mode=$(stat -c %a "$cache_root")
(( (8#$cache_mode & 0022) == 0 )) || die 'Cache directory must not be group/world writable.'
exec 9> "$cache_root/.lock"
flock -n 9 || die 'Another ISO launcher is using this cache. Wait for it to finish.'
payload_container="$cache_root/$payload_digest"
bundle_dir="$payload_container/$bundle_name"
stage=''
cleanup() {
    rc=$?
    if [[ -n $stage && -d $stage ]]; then rm -rf -- "$stage"; fi
    exit "$rc"
}
trap cleanup EXIT
if [[ ! -e $payload_container ]]; then
    stage=$(mktemp -d "$cache_root/.prepare.XXXXXXXX")
    chmod 0755 "$stage"
    printf 'Preparing local payload from read-only media...\n'
    # build-kernel-iso.sh admits only a single-root, regular-file/directory tar
    # with verified internal checksums; the ISO checksums protect its bytes.
    tar --extract --gzip --file="$media_dir/payload/$payload_file" --directory="$stage" \
        --no-same-owner --no-same-permissions
    [[ -f $stage/$bundle_name/install-kernel.sh && -f $stage/$bundle_name/SHA256SUMS ]] || die 'Incomplete extracted bundle.'
    cmp -s "$stage/$bundle_name/SHA256SUMS" "$media_dir/payload-SHA256SUMS" || die 'Extracted checksum manifest mismatch.'
    (cd "$stage/$bundle_name" && sha256sum --strict -c "$media_dir/payload-SHA256SUMS" > /dev/null) || die 'Extracted bundle integrity check failed.'
    printf '%s\n' "$payload_digest" > "$stage/.payload-sha256"
    mv -- "$stage" "$payload_container"
    stage=''
fi
[[ -d $bundle_dir && -f $payload_container/.payload-sha256 ]] || die "Incomplete existing cache: $payload_container"
[[ $(cat "$payload_container/.payload-sha256") == "$payload_digest" ]] || die 'Existing cache identity mismatch.'
cmp -s "$bundle_dir/SHA256SUMS" "$media_dir/payload-SHA256SUMS" || die 'Cached manifest has changed.'
(cd "$bundle_dir" && sha256sum --strict -c "$media_dir/payload-SHA256SUMS" > /dev/null) || die 'Cached bundle integrity check failed.'
[[ ! -e $cache_root/current || -L $cache_root/current ]] || die "$cache_root/current must be a symlink or absent."
ln -sfnT -- "$bundle_dir" "$cache_root/current"
printf 'Verified local bundle: %s\nLogs: %s/logs/\n' "$bundle_dir" "$bundle_dir"
printf 'After reboot, ISO is not required for verification:\n'
printf 'sudo bash %s/current/install-kernel.sh verify\n\n' "$cache_root"
# Keep the lock in this parent; do not leak its descriptor into APT/dpkg hooks.
bash "$bundle_dir/install-kernel.sh" "$mode" 9>&-
