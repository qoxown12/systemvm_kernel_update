#!/usr/bin/env bash
# Download-only builder. Never installs packages on the downloader.
set -Eeuo pipefail
export LC_ALL=C
umask 022
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'USAGE'
Usage: sudo bash prepare-debian12-kernel-offline.sh [output-directory]
       [--target-status FILE ...] [--extra-package NAME ...]
Default output: /var/tmp/debian12-kernel-offline
Requires Debian 12 amd64, APT, dpkg-deb, curl, python3 (no dpkg-dev needed).
Keep kernel-offline-tools.py, kernel-boot-check.sh, install-kernel-offline.sh, README-KO.txt and
collect-systemvm-state.sh beside this script.
Target status files are optional; pass one per distinct SystemVM package state.
USAGE
}
output_dir=/var/tmp/debian12-kernel-offline
output_seen=false
target_states=()
roots=(linux-image-amd64 initramfs-tools linux-base kmod busybox zstd)
while (( $# )); do
    case $1 in
        -h|--help) usage; exit 0 ;;
        --target-status)
            [[ $# -ge 2 && -s $2 ]] || die '--target-status requires a nonempty dpkg status file.'
            target_states+=("$(realpath -- "$2")")
            shift 2 ;;
        --extra-package)
            [[ $# -ge 2 && $2 =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || die '--extra-package requires a package name.'
            roots+=("$2"); shift 2 ;;
        -*) die "Unknown option: $1" ;;
        *) [[ $output_seen == false ]] || die 'Only one output directory is allowed.'
           output_dir=$1; output_seen=true; shift ;;
    esac
done
[[ $EUID -eq 0 ]] || die 'Run as root.'
source /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 12 ]] || die 'Requires Debian 12.'
[[ $(dpkg --print-architecture) == amd64 ]] || die 'Requires amd64.'
for cmd in apt-get apt-cache apt-config dpkg-deb sha256sum tar gzip curl python3 realpath; do
    command -v "$cmd" >/dev/null || die "Missing command: $cmd"
done
[[ -r /usr/share/keyrings/debian-archive-keyring.gpg ]] || die 'Install debian-archive-keyring first.'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
for file in kernel-offline-tools.py kernel-boot-check.sh install-kernel-offline.sh collect-systemvm-state.sh README-KO.txt; do
    [[ -r $script_dir/$file ]] || die "Missing companion file: $script_dir/$file"
done
mkdir -p -- "$output_dir"
output_dir=$(cd -- "$output_dir" && pwd -P)
[[ $output_dir =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Use a simple absolute output path without spaces.'
work_dir=$(mktemp -d "$output_dir/build.XXXXXXXX")
chmod 0755 "$work_dir"
bundle_name="debian12-kernel-amd64-$(date -u +%Y%m%dT%H%M%SZ)-${work_dir##*.}"
bundle_dir="$work_dir/$bundle_name"
mkdir -p "$work_dir/lists/partial" "$work_dir/empty.d" "$work_dir/log" \
    "$bundle_dir/repo/partial" "$bundle_dir/validation" "$bundle_dir/evidence"
touch "$work_dir/empty-status" "$work_dir/extended_states" "$work_dir/empty.conf"
trap 'rc=$?; printf "ERROR: line %s failed (%s). Incomplete build retained: %s\n" "$LINENO" "$rc" "$work_dir" >&2; exit "$rc"' ERR
run_log() {
    local logfile=$1
    shift
    if ! "$@" > "$logfile" 2>&1; then
        tail -n 80 "$logfile" >&2
        die "Command failed; see $logfile"
    fi
}
printf '[1/6] Reading CVE-2026-43499 fixed version from Debian tracker\n'
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 20 --max-time 120 \
    https://security-tracker.debian.org/tracker/CVE-2026-43499 \
    -o "$bundle_dir/CVE-2026-43499.html"
python3 "$script_dir/kernel-offline-tools.py" tracker "$bundle_dir/CVE-2026-43499.html" > "$bundle_dir/cve-fixed-version.txt"
minimum=$(cat "$bundle_dir/cve-fixed-version.txt")
printf 'Bookworm linux fixed since: %s\n' "$minimum"
cat > "$work_dir/sources.list" <<'SOURCES'
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian bookworm main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian bookworm-updates main
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://security.debian.org/debian-security bookworm-security main
SOURCES
# APT_CONFIG is read BEFORE host apt.conf fragments, unlike -c alone.
cat > "$work_dir/download.conf" <<CONFIG
Dir::Etc::parts "$work_dir/empty.d";
Dir::Etc::main "$work_dir/empty.conf";
Dir::Etc::sourcelist "$work_dir/sources.list";
Dir::Etc::sourceparts "$work_dir/empty.d";
Dir::Etc::preferences "$work_dir/empty.conf";
Dir::Etc::preferencesparts "$work_dir/empty.d";
Dir::State::status "$work_dir/empty-status";
Dir::State::extended_states "$work_dir/extended_states";
Dir::State::lists "$work_dir/lists";
Dir::Cache::archives "$bundle_dir/repo";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
Dir::Log "$work_dir/log";
APT::Architecture "amd64";
#clear APT::Architectures;
APT::Architectures { "amd64"; };
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Languages "none";
Acquire::GzipIndexes "true";
Acquire::Retries "3";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::AllowInsecureRepositories "false";
APT::Get::AllowUnauthenticated "false";
CONFIG
online_apt() { APT_CONFIG="$work_dir/download.conf" /usr/bin/apt-get "$@"; }
online_cache() { APT_CONFIG="$work_dir/download.conf" /usr/bin/apt-cache "$@"; }
printf '[2/6] Updating authenticated bookworm indexes (no host APT changes)\n'
run_log "$bundle_dir/validation/online-update.log" online_apt -o APT::Update::Error-Mode=any update
online_cache policy linux-image-amd64 > "$bundle_dir/evidence/kernel-policy.txt"
cat "$bundle_dir/evidence/kernel-policy.txt"
candidate=$(online_cache policy linux-image-amd64 | awk '/Candidate:/ {print $2}')
[[ $candidate =~ ^6\.1\.[0-9]+-[0-9A-Za-z.+~]+$ ]] || die "Unexpected bookworm candidate: $candidate"
dpkg --compare-versions "$candidate" ge "$minimum" || die "Candidate $candidate is below CVE fixed version $minimum"
printf '%s\n' "${roots[@]}" > "$bundle_dir/roots.txt"
printf '[3/6] Downloading kernel and full selected dependency closure with EMPTY dpkg state\n'
run_log "$bundle_dir/validation/empty-download.log" online_apt --yes --download-only --no-remove \
    --no-install-recommends install "linux-image-amd64=$candidate" "${roots[@]:1}"
# Metadata inspection identifies the exact signed kernel; rebuild again after
# target-state union, because those plans can add more dependency packages.
python3 "$script_dir/kernel-offline-tools.py" index "$bundle_dir"
kernel_pkg=$(cat "$bundle_dir/kernel-package.txt")
kernel_ver=$(cat "$bundle_dir/kernel-version.txt")
[[ $kernel_ver == "$candidate" ]] || die 'Repository changed while downloading. Retry in a new build.'
dpkg --compare-versions "$kernel_ver" ge "$minimum" || die 'Downloaded kernel is below CVE fixed version.'
targets=("$kernel_pkg=$kernel_ver" "linux-image-amd64=$candidate" "${roots[@]:1}")
printf 'State\tSHA256\n' > "$bundle_dir/evidence/target-states.tsv"
state_copies=()
for i in "${!target_states[@]}"; do
    state="${target_states[$i]}"
    copy="$work_dir/target-$i.status"
    cp -- "$state" "$copy"
    # A status file must contain installed package records, not an empty/foreign file.
    grep -Eq '^Status: (install|hold) ok installed$' "$copy" || die "Invalid target status: $state"
    if grep -E '^Architecture: ' "$copy" | grep -Ev '^Architecture: (amd64|all|i386)$' > /dev/null; then
        die "Target status contains unsupported architectures: $state"
    fi
    state_copies+=("$copy")
    digest=$(sha256sum "$copy"); digest=${digest%% *}
    printf 'target-%s\t%s\n' "$i" "$digest" >> "$bundle_dir/evidence/target-states.tsv"
    printf 'Collecting additional dependency plan for target-%s\n' "$i"
    run_log "$bundle_dir/validation/target-$i-download.log" online_apt -o "Dir::State::status=$copy" \
        --yes --download-only --no-remove --no-install-recommends install "${targets[@]}"
done
printf '[4/6] Creating local APT index and package manifest\n'
python3 "$script_dir/kernel-offline-tools.py" index "$bundle_dir"
gzip -n -9 -c "$bundle_dir/repo/Packages" > "$bundle_dir/repo/Packages.gz"
cp "$work_dir/sources.list" "$bundle_dir/download-sources.list"
cp "$script_dir/install-kernel-offline.sh" "$bundle_dir/install-kernel.sh"
cp "$script_dir/collect-systemvm-state.sh" "$script_dir/kernel-boot-check.sh" "$script_dir/README-KO.txt" "$bundle_dir/"
boot_revision=$(awk -F= '$1=="grub_boot_revision" {print $2}' "$script_dir/kernel-boot-check.sh")
[[ $boot_revision =~ ^[0-9]{8}-[a-z0-9-]+$ ]] || die 'Missing or invalid boot checker revision.'
printf '%s\n' "$boot_revision" > "$bundle_dir/BOOT-CONFIG-REVISION.txt"
chmod 0755 "$bundle_dir/install-kernel.sh" "$bundle_dir/collect-systemvm-state.sh"
mkdir -p "$bundle_dir/source"
cp "$script_dir/prepare-debian12-kernel-offline.sh" "$script_dir/kernel-offline-tools.py" \
    "$script_dir/install-kernel-offline.sh" "$script_dir/kernel-boot-check.sh" "$script_dir/collect-systemvm-state.sh" \
    "$script_dir/README-KO.txt" "$bundle_dir/source/"
if [[ -f $script_dir/tests/verify_bundle.py ]]; then
    mkdir -p "$bundle_dir/source/tests"
    cp "$script_dir/tests/verify_bundle.py" "$bundle_dir/source/tests/"
fi
if [[ -f $script_dir/tests/test_grub_boot.py ]]; then
    mkdir -p "$bundle_dir/source/tests"
    cp "$script_dir/tests/test_grub_boot.py" "$bundle_dir/source/tests/"
fi
for extra in build-kernel-iso.sh run-kernel-from-iso.sh; do
    if [[ -f $script_dir/$extra ]]; then cp -- "$script_dir/$extra" "$bundle_dir/source/"; fi
done
for doc in BUILD.md INSTALL.md BUNDLE-USAGE.md plan.md; do
    if [[ -f $script_dir/$doc ]]; then cp -- "$script_dir/$doc" "$bundle_dir/"; fi
done
# Keep signed Release metadata and exact upstream records for provenance.
shopt -s nullglob
releases=("$work_dir"/lists/*InRelease)
(( ${#releases[@]} == 3 )) || die 'Expected three authenticated Debian InRelease files.'
cp -- "${releases[@]}" "$bundle_dir/evidence/"
upstream_specs=()
while IFS=$'\t' read -r pkg ver arch file size; do
    [[ $pkg == Package ]] && continue
    upstream_specs+=("$pkg=$ver")
done < "$bundle_dir/packages.tsv"
online_cache show "${upstream_specs[@]}" > "$bundle_dir/evidence/upstream-packages.txt"
{
    printf 'Created UTC: %s\nDownloader OS: %s\nDownloader running kernel: %s\n' "$(date -u +%FT%TZ)" "$PRETTY_NAME" "$(uname -r)"
    printf 'Target: Debian 12 / bookworm / amd64\nCVE: CVE-2026-43499\nFixed since (linux): %s\n' "$minimum"
    printf 'Kernel: %s=%s\nAdditional real target statuses: %s\n' "$kernel_pkg" "$kernel_ver" "${#state_copies[@]}"
    printf 'Closure: empty dpkg status + optional real target status plans; no removals.\n'
    printf 'Root packages: %s\n' "${roots[*]}"
    printf 'No downloader packages installed; no target packages installed or boot tested by builder.\n'
    printf 'Recommends/Suggests, all alternative providers, headers, DKMS, firmware and bootloader replacement are outside the generic closure.\n'
    printf 'Linux signed binary Debian Version compared against linux source fixed version (not linux-signed-amd64 Source).\n'
} > "$bundle_dir/BUILD-INFO.txt"
printf '[5/6] Re-solving using ONLY the completed local repository\n'
mkdir -p "$work_dir/local-lists/partial"
sed -e "s|$work_dir/sources.list|$work_dir/local.list|g" \
    -e "s|$work_dir/lists|$work_dir/local-lists|g" \
    "$work_dir/download.conf" > "$work_dir/local.conf"
printf 'deb [trusted=yes] file:%s/repo ./\n' "$bundle_dir" > "$work_dir/local.list"
local_apt() { APT_CONFIG="$work_dir/local.conf" /usr/bin/apt-get "$@"; }
run_log "$bundle_dir/validation/local-update.log" local_apt -o APT::Update::Error-Mode=any update
run_log "$bundle_dir/validation/empty-local-simulation.txt" local_apt --simulate --no-remove \
    --no-install-recommends install "${targets[@]}"
for i in "${!state_copies[@]}"; do
    run_log "$bundle_dir/validation/target-$i-local-simulation.txt" local_apt \
        -o "Dir::State::status=${state_copies[$i]}" --simulate --no-remove --no-install-recommends install "${targets[@]}"
done
printf '[6/6] Checksumming and packaging the verified local repository\n'
(
    cd "$bundle_dir"
    find . -type f ! -path './repo/lock' ! -path './repo/partial/*' ! -name SHA256SUMS -print0 |
        sort -z | xargs -0 sha256sum > SHA256SUMS
    sha256sum --strict -c SHA256SUMS > "$work_dir/checksums.log"
)
archive="$output_dir/$bundle_name.tar.gz"
# An interrupted tar is .partial, never a completed transfer artifact.
tar --exclude='*/repo/partial' --exclude='*/repo/lock' -C "$work_dir" -czf "$archive.partial" "$bundle_name"
mv -- "$archive.partial" "$archive"
(cd "$output_dir" && sha256sum "$bundle_name.tar.gz" > "$bundle_name.tar.gz.sha256")
count=$(find "$bundle_dir/repo" -maxdepth 1 -name '*.deb' | wc -l)
printf '\nSUCCESS: %s packages\nKernel: %s=%s\nCVE fixed since: %s\n' "$count" "$kernel_pkg" "$kernel_ver" "$minimum"
printf 'Archive: %s\nChecksum: %s.sha256\nExtracted bundle: %s\n' "$archive" "$archive" "$bundle_dir"
printf 'No kernel was installed. Transfer archive + checksum, then run install-kernel.sh check on each target.\n'
