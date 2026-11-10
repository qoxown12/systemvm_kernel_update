#!/usr/bin/env bash
# Controller: cloud SSH -> sudo worker -> check/install/check-boot -> reboot -> verify.
# Controller baseline: Rocky Linux 9, Bash 4.4+, Python 3.9+, openssh-clients.
# This script never copies the SSH private key to the target.
set -Eeuo pipefail
export LC_ALL=C
umask 077
rollout_revision=20261106-rocky9-cks-1
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: bash deploy-systemvm-kernel.sh -k SSH_KEY -f PATCH.tar.gz -i TARGET_IP -p SSH_PORT [options]
       bash deploy-systemvm-kernel.sh -k SSH_KEY -i TARGET_IP -p SSH_PORT --verify-only RUN_ID
  -k, --key FILE         SSH private key file (used locally only)
  -f, --archive FILE     Kernel tar.gz (requires its adjacent .sha256)
  -i, --ip ADDRESS       Target VM IP address; account is cloud
  -p, --port PORT        Target SSH port (required; no default)
  --check-only            Identity, transfer, extraction and check; no install/reboot
  --verify-only RUN_ID    Recheck a previous apply run; no transfer/install/reboot
  --scp-legacy            Use legacy scp -O if target SFTP is unavailable
  --install-timeout SEC   Wait for detached installer (default: 1800)
  --reboot-timeout SEC    Wait for a different boot ID and SSH (default: 900)
  --service-timeout SEC   Wait for systemd/services after boot (default: 180)
  -h, --help             Show this help
Account: cloud. Passwordless sudo and key-based SSH are required.
Controller: Rocky Linux 9 (Python 3.9+, openssh-clients, coreutils, gawk).
Target: Debian 12 amd64 AbleStack SystemVM or SystemVM-template-based CKS node.
Default mode INSTALLS AND REBOOTS the target after successful checks.
HELP
    printf 'Revision: %s\n' "$rollout_revision"
}
[[ $# -gt 0 ]] || { usage >&2; exit 1; }
key_input='' target_ip='' ssh_port='' archive_input=''
mode=apply resume_id='' scp_legacy=false
install_timeout=1800 reboot_timeout=900 service_timeout=180
while (( $# )); do
    case $1 in
        -k|--key|-f|--archive|-i|--ip|-p|--port|--verify-only|--install-timeout|--reboot-timeout|--service-timeout)
            [[ $# -ge 2 && -n $2 && $2 != -* ]] || die "Missing value for $1"
            case $1 in
                -k|--key) [[ -z $key_input ]] || die 'Duplicate option: -k/--key'; key_input=$2 ;;
                -f|--archive) [[ -z $archive_input ]] || die 'Duplicate option: -f/--archive'; archive_input=$2 ;;
                -i|--ip) [[ -z $target_ip ]] || die 'Duplicate option: -i/--ip'; target_ip=$2 ;;
                -p|--port) [[ -z $ssh_port ]] || die 'Duplicate option: -p/--port'; ssh_port=$2 ;;
                --verify-only) [[ $mode == apply ]] || die 'Choose only one mode.'; mode=verify; resume_id=$2 ;;
                --install-timeout) install_timeout=$2 ;;
                --reboot-timeout) reboot_timeout=$2 ;;
                --service-timeout) service_timeout=$2 ;;
            esac
            shift 2 ;;
        --check-only) [[ $mode == apply ]] || die 'Choose only one mode.'; mode=check; shift ;;
        --scp-legacy) scp_legacy=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option or positional argument: $1. Use -k KEY -f FILE -i IP -p PORT; see --help." ;;
    esac
done
[[ -n $key_input ]] || die 'Required option missing: -k SSH_KEY'
[[ -n $target_ip ]] || die 'Required option missing: -i TARGET_IP'
[[ -n $ssh_port ]] || die 'Required option missing: -p SSH_PORT'
[[ $mode == verify || -n $archive_input ]] || die 'Required option missing: -f PATCH.tar.gz'
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) || die 'Controller requires Bash 4.4 or newer.'
for cmd in ssh scp python3 sha256sum realpath timeout tee mktemp awk tail date; do
    command -v "$cmd" >/dev/null || die "Missing local command: $cmd. On Rocky Linux 9: sudo dnf install -y bash python3 openssh-clients coreutils gawk"
done
python3 - "$target_ip" "$ssh_port" "$install_timeout" "$reboot_timeout" "$service_timeout" <<'PY'
import ipaddress, sys
if sys.version_info < (3, 9):
    raise SystemExit('ERROR: controller requires Python 3.9 or newer; install the Rocky Linux 9 python3 package')
try:
    ipaddress.ip_address(sys.argv[1])
    assert '%' not in sys.argv[1] and '[' not in sys.argv[1]
    assert sys.argv[2].isascii() and sys.argv[2].isdecimal() and 1 <= int(sys.argv[2]) <= 65535
    assert all(v.isascii() and v.isdecimal() and 1 <= int(v) <= 86400 for v in sys.argv[3:])
except (ValueError, AssertionError):
    raise SystemExit('ERROR: use a valid numeric IP, port 1..65535 and timeouts 1..86400 seconds')
PY
ssh_port=$((10#$ssh_port))
install_timeout=$((10#$install_timeout))
reboot_timeout=$((10#$reboot_timeout))
service_timeout=$((10#$service_timeout))
key_file=$(realpath -- "$key_input")
[[ -f $key_file && -r $key_file ]] || die 'SSH key file is not readable.'
if [[ $mode != verify ]]; then
    archive_file=$(realpath -- "$archive_input")
    [[ -f $archive_file && -f $archive_file.sha256 ]] || die 'Archive and adjacent .tar.gz.sha256 are required.'
fi
[[ $mode != verify || $resume_id =~ ^[0-9]{8}T[0-9]{6}Z-[a-zA-Z0-9]{8}$ ]] || die 'Invalid RUN_ID.'
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(mktemp -u XXXXXXXX)"
[[ $mode != verify ]] || run_id=$resume_id
log_dir=$(mktemp -d "$PWD/systemvm-rollout-$run_id-XXXXXXXX")
worker="$log_dir/remote-worker.sh"
exec > >(tee "$log_dir/controller.log") 2>&1
printf 'Mode: %s | Target: cloud@%s:%s | Run: %s\nLocal logs: %s\n' "$mode" "$target_ip" "$ssh_port" "$run_id" "$log_dir"
printf 'Revision: %s\n' "$rollout_revision"
printf 'Controller Python: %s\n' "$(python3 --version 2>&1)"
scp_protocol_options=()
transfer_protocol='SFTP (scp default on Rocky Linux 9)'
if [[ $scp_legacy == true ]]; then
    scp_protocol_options=(-O)
    transfer_protocol='legacy SCP (-O, explicitly requested)'
fi
ssh_options=(-i "$key_file" -o BatchMode=yes -o IdentitiesOnly=yes
    -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o ForwardAgent=no
    -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no
    -o ControlMaster=no -o ControlPath=none -o ConnectTimeout=10 -o ConnectionAttempts=1
    -o ServerAliveInterval=10 -o ServerAliveCountMax=2 -o LogLevel=ERROR)
ssh_target="cloud@$target_ip"
scp_target=$ssh_target
[[ $target_ip != *:* ]] || scp_target="cloud@[$target_ip]"

# Standalone Bash worker, copied without credentials and installed root-owned.
cat > "$worker" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 022
base=/var/lib/systemvm-kernel-rollout
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die 'Passwordless sudo to root is required.'
systemvm_identity() {
    local unit
    source /etc/os-release
    [[ ${ID:-} == debian && ${VERSION_ID:-} == 12 && $(dpkg --print-architecture) == amd64 ]] || die 'Requires Debian 12 amd64.'
    for command_name in systemctl systemd-run systemd-detect-virt flock sha256sum tar timeout dd; do
        command -v "$command_name" >/dev/null || die "Missing remote command: $command_name"
    done
    [[ -d /run/systemd/system ]] || die 'Systemd is not running.'
    systemd-detect-virt --vm --quiet || die 'Target is not identified as a virtual machine.'
    [[ -s /etc/ablestack-release && -s /opt/cloud/bin/setup/common.sh && -s /var/cache/cloud/cmdline ]] ||
        die 'AbleStack template markers missing. No transfer/install/reboot is permitted.'
    # Never source or print cmdline: it can contain credentials and private keys.
    role=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^type=/) {sub(/^type=/,"",$i); print $i}}' /var/cache/cloud/cmdline)
    [[ -n $role ]] || die 'AbleStack type= marker is missing.'
    [[ $role != *$'\n'* ]] || die 'Multiple AbleStack type= markers found; review the target identity.'
    vm_class=systemvm
    cks_primary_unit=''
    case $role in
        router|vpcrouter|dhcpsrvr|secstorage|consoleproxy|internallbvm) ;;
        cksnode)
            vm_class=cksnode
            # CKS uses the SystemVM template too, but has Kubernetes services
            # rather than SSVM/CPVM cloud.service. Also allow dedicated etcd nodes.
            for unit in kubelet.service etcd.service; do
                if [[ $(systemctl show "$unit" -p LoadState --value 2>/dev/null) == loaded ]]; then
                    cks_primary_unit=$unit
                    break
                fi
            done
            [[ -n $cks_primary_unit ]] || die 'type=cksnode found, but neither kubelet.service nor etcd.service is loaded. Review CKS node setup.'
            ;;
        *) die 'Unsupported AbleStack VM type; this target is not a supported SystemVM or CKS node.' ;;
    esac
    [[ -s /etc/machine-id ]] || die 'Missing machine ID.'
    identity=$({ cat /etc/machine-id; [[ ! -r /sys/class/dmi/id/product_uuid ]] || cat /sys/class/dmi/id/product_uuid; printf '\n%s\n' "$role"; } | sha256sum)
    identity=${identity%% *}
    boot_id=$(cat /proc/sys/kernel/random/boot_id)
    [[ $boot_id =~ ^[a-f0-9-]{36}$ ]] || die 'Invalid boot ID.'
}
state_for() {
    [[ ${1:-} =~ ^[0-9]{8}T[0-9]{6}Z-[a-zA-Z0-9]{8}$ ]] || die 'Invalid run ID.'
    state="$base/$1"
}
status_write() {
    printf '%s\n' "$1" > "$state/status.$$"
    mv -f -- "$state/status.$$" "$state/status"
}
fail_job() {
    local rc=$?
    trap - EXIT
    if (( rc != 0 )); then
        printf 'Failed phase: %s, exit: %s\n' "${phase:-unknown}" "$rc" > "$state/error.txt"
        status_write FAILED
        printf 'ERROR: phase %s failed (exit %s); no further steps.\n' "${phase:-unknown}" "$rc" >&2
    fi
    exit "$rc"
}
lock_target() {
    exec 9> /run/lock/systemvm-kernel-rollout.lock
    flock -n 9 || die 'Another kernel rollout/verification is running on this target.'
}
same_identity() {
    systemvm_identity
    [[ $identity == "$(cat "$state/identity.txt")" ]] || die 'AbleStack VM identity changed. Refusing to continue.'
}
services_snapshot() {
    systemctl --failed --type=service --no-legend --plain --no-pager > "$state/services-before.txt"
    systemctl list-units --type=service --state=active --no-legend --plain --no-pager > "$state/active-before.txt"
    : > "$state/required-services.txt"
    while read -r unit rest; do
        [[ $unit == *.service ]] || continue
        substate=$(systemctl show "$unit" -p SubState --value)
        unit_file_state=$(systemctl show "$unit" -p UnitFileState --value)
        [[ $substate == running && $unit_file_state != transient ]] || continue
        [[ $unit =~ ^[a-zA-Z0-9@_.-]+\.service$ ]] || die "Unsupported service name: $unit"
        printf '%s\n' "$unit" >> "$state/required-services.txt"
    done < "$state/active-before.txt"
    printf 'ssh.service\n' >> "$state/required-services.txt"
    if [[ $role == secstorage || $role == consoleproxy ]]; then
        [[ $(systemctl show cloud.service -p LoadState --value) == loaded ]] || die 'SystemVM cloud.service is missing.'
        printf 'cloud.service\n' >> "$state/required-services.txt"
    fi
    if [[ $role == cksnode ]]; then
        printf '%s\n' "$cks_primary_unit" >> "$state/required-services.txt"
        printf 'CKS node identified; Kubernetes service required after boot: %s\n' "$cks_primary_unit"
    fi
    # CKS can retain SystemVM template service declarations; use its Kubernetes
    # primary unit and the running-service baseline rather than unused agent roles.
    if [[ $role != cksnode && -r /var/cache/cloud/enabled_svcs ]]; then
        while read -r token; do
            [[ $token =~ ^[a-zA-Z0-9@_.-]+$ ]] || die 'Invalid enabled_svcs service name.'
            unit=${token%.service}.service
            load_state=$(systemctl show "$unit" -p LoadState --value)
            if [[ $load_state == loaded ]]; then
                printf '%s\n' "$unit" >> "$state/required-services.txt"
            fi
        done < <(awk '{for(i=1;i<=NF;i++) print $i}' /var/cache/cloud/enabled_svcs)
    fi
    sort -u -o "$state/required-services.txt" "$state/required-services.txt"
    printf 'Services required after boot:\n'; cat "$state/required-services.txt"
}
action=${1:-}
shift || true
case $action in
    probe)
        systemvm_identity
        printf 'SYSTEMVM_ID=%s\nSYSTEMVM_BOOT_ID=%s\nSYSTEMVM_ROLE=%s\nABLECLOUD_VM_CLASS=%s\n' "$identity" "$boot_id" "$role" "$vm_class"
        ;;
    upload-dir)
        systemvm_identity
        [[ $identity == "$1" ]] || die 'Target identity changed.'
        cloud_home=$(getent passwd cloud | cut -d: -f6)
        [[ $cloud_home =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Unsupported cloud home path.'
        upload=$(mktemp -d "$cloud_home/.systemvm-kernel-upload.XXXXXXXX")
        chown cloud -- "$upload"
        chmod 0700 "$upload"
        printf 'UPLOAD_DIR=%s\n' "$upload"
        ;;
    prepare)
        # upload digest worker-digest run-id bundle-name expected-identity boot-id mode service-timeout
        [[ $# -eq 9 ]] || die 'Invalid prepare arguments.'
        upload=$1 digest=$2 worker_digest=$3
        state_for "$4"
        bundle_name=$5 expected_identity=$6 expected_boot=$7 run_mode=$8 health_timeout=$9
        [[ $digest =~ ^[a-f0-9]{64}$ && $worker_digest =~ ^[a-f0-9]{64}$ && $bundle_name =~ ^debian12-kernel-amd64-[A-Za-z0-9_.-]+$ ]] || die 'Invalid payload metadata.'
        [[ $run_mode == apply || $run_mode == check ]] || die 'Invalid run mode.'
        [[ $health_timeout =~ ^[0-9]+$ ]] || die 'Invalid service timeout.'
        systemvm_identity
        [[ $identity == "$expected_identity" && $boot_id == "$expected_boot" ]] || die 'Target identity/boot changed before preparation.'
        cloud_home=$(getent passwd cloud | cut -d: -f6)
        [[ $upload == "$cloud_home"/.systemvm-kernel-upload.* && ${upload##*/} =~ ^\.systemvm-kernel-upload\.[a-zA-Z0-9]{8}$ && ! -L $upload ]] || die 'Invalid upload path.'
        for file in payload.tar.gz worker.sh; do
            [[ -f $upload/$file && ! -L $upload/$file ]] || die 'Missing upload or unexpected symlink.'
        done
        [[ ! -L $base ]] || die 'State base must not be a symlink.'
        mkdir -p -- "$base"
        [[ $(stat -c %u "$base") == 0 ]] || die 'State base must be owned by root.'
        permissions=$(stat -c %a "$base")
        (( (8#$permissions & 0022) == 0 )) || die 'State base must not be group/world writable.'
        mkdir -m 0755 -- "$state"
        # Create regular root-owned copies; refuse final-component symlinks and
        # keep unverified uploads private until their hashes have been checked.
        (umask 077; dd if="$upload/payload.tar.gz" of="$state/payload.tar.gz" iflag=nofollow status=none)
        (umask 077; dd if="$upload/worker.sh" of="$state/worker.sh" iflag=nofollow status=none)
        printf '%s  %s\n%s  %s\n' "$digest" "$state/payload.tar.gz" "$worker_digest" "$state/worker.sh" | sha256sum --strict -c -
        chmod 0644 "$state/payload.tar.gz"
        chmod 0700 "$state/worker.sh"
        printf '%s\n' "$identity" > "$state/identity.txt"
        printf '%s\n' "$boot_id" > "$state/boot-before.txt"
        printf '%s\n' "$bundle_name" > "$state/bundle-name.txt"
        printf '%s\n' "$run_mode" > "$state/mode.txt"
        printf '%s\n' "$health_timeout" > "$state/service-timeout.txt"
        # Finish upload cleanup before starting the independent modifying job.
        rm -f -- "$upload/payload.tar.gz" "$upload/worker.sh"
        rmdir -- "$upload"
        status_write STARTING
        # SSH disconnection does not terminate an APT/dpkg operation.
        systemd-run --quiet --collect --unit="systemvm-kernel-$4" \
            --property=Type=exec /bin/bash "$state/worker.sh" run "$4" || {
            status_write FAILED
            die 'Failed to start the root worker; no installer was launched.'
        }
        printf 'REMOTE_STATE=%s\n' "$state"
        ;;
    run)
        state_for "$1"
        exec >> "$state/run.log" 2>&1
        phase=LOCK
        trap fail_job EXIT
        lock_target
        phase=IDENTITY
        same_identity
        [[ $boot_id == "$(cat "$state/boot-before.txt")" ]] || die 'Boot changed before worker started.'
        bundle_name=$(cat "$state/bundle-name.txt")
        run_mode=$(cat "$state/mode.txt")
        phase=SERVICES_BEFORE
        services_snapshot
        phase=EXTRACTING; status_write "$phase"
        mkdir -m 0755 -- "$state/extracted"
        tar --extract --gzip --file="$state/payload.tar.gz" --directory="$state/extracted" --no-same-owner --no-same-permissions
        bundle="$state/extracted/$bundle_name"
        cd "$bundle"
        sha256sum --strict -c SHA256SUMS > "$state/payload-checksums.log"
        phase=CHECK; status_write "$phase"
        bash ./install-kernel.sh check 9>&-
        if [[ $run_mode == check ]]; then
            status_write COMPLETE_CHECK
            printf 'Check-only completed. No packages installed or reboot requested.\n'
            exit 0
        fi
        phase=INSTALL; status_write "$phase"
        bash ./install-kernel.sh install 9>&-
        phase=CHECK_BOOT; status_write "$phase"
        bash ./install-kernel.sh check-boot 9>&-
        phase=REBOOT_SCHEDULING
        # Separate timer survives SSH loss. It is created only once, after all checks.
        systemd-run --quiet --collect --unit="systemvm-kernel-$1-reboot" --on-active=5s \
            /usr/bin/systemctl --no-wall reboot
        status_write REBOOT_PENDING
        printf 'Reboot scheduled. Waiting for shutdown; rollout lock remains held.\n'
        trap 'exit 0' TERM INT
        sleep 120
        die 'Reboot did not occur within 120 seconds. No second reboot was requested.'
        ;;
    status)
        state_for "$1"
        [[ -f $state/status ]] || die 'Run state not found.'
        cat "$state/status"
        ;;
    verify)
        state_for "$1"
        [[ -f $state/mode.txt && $(cat "$state/mode.txt") == apply ]] || die 'An apply run is required for post-reboot verification.'
        exec > >(tee -a "$state/verify.log") 2>&1
        phase=POSTBOOT_LOCK
        trap fail_job EXIT
        lock_target
        phase=SYSTEMD_STARTUP
        health_timeout=${2:-$(cat "$state/service-timeout.txt")}
        [[ $health_timeout =~ ^[0-9]+$ ]] && (( health_timeout >= 1 && health_timeout <= 86400 )) || die 'Invalid health timeout.'
        health_state=$(timeout "$health_timeout" systemctl is-system-running --wait 2>/dev/null) || true
        [[ $health_state == running || $health_state == degraded ]] || die "Systemd startup not complete: ${health_state:-unknown}"
        phase=POSTBOOT_IDENTITY
        same_identity
        [[ $boot_id != "$(cat "$state/boot-before.txt")" ]] || die 'Boot ID did not change; a completed reboot is required.'
        phase=KERNEL_VERIFY
        bundle_name=$(cat "$state/bundle-name.txt")
        bundle="$state/extracted/$bundle_name"
        bash "$bundle/install-kernel.sh" verify 9>&-
        audit=$(dpkg --audit)
        [[ -z $audit ]] || die "Postboot dpkg audit failed: $audit"
        uname -r
        cat /proc/version
        phase=SERVICE_HEALTH
        deadline=$((SECONDS + health_timeout))
        while :; do
            systemctl --failed --no-legend --plain --no-pager > "$state/failed-after.txt"
            : > "$state/inactive-after.txt"
            while IFS= read -r unit; do
                [[ $unit =~ ^[a-zA-Z0-9@_.-]+\.service$ ]] || die 'Invalid saved service name.'
                if ! systemctl is-active --quiet "$unit"; then printf '%s\n' "$unit" >> "$state/inactive-after.txt"; fi
            done < "$state/required-services.txt"
            if [[ ! -s $state/failed-after.txt && ! -s $state/inactive-after.txt ]]; then break; fi
            if (( SECONDS >= deadline )); then
                printf 'Failed units:\n'; cat "$state/failed-after.txt"
                printf 'Required services not active:\n'; cat "$state/inactive-after.txt"
                die 'Post-reboot service health check failed. No automatic repair/reboot performed.'
            fi
            sleep 5
        done
        systemctl --failed --no-pager
        printf 'AbleStack VM type: %s (%s); required services active; failed units: 0\n' "$role" "$vm_class"
        status_write VERIFIED
        printf 'Kernel and local services verified. Validate AbleStack/Kubernetes role functions separately.\n'
        ;;
    logs)
        state_for "$1"
        for file in error.txt run.log verify.log services-before.txt required-services.txt failed-after.txt inactive-after.txt; do
            if [[ -f $state/$file ]]; then printf '\n--- %s ---\n' "$file"; cat "$state/$file"; fi
        done
        ;;
    *) die 'Invalid worker action.' ;;
esac
REMOTE

remote_action() {
    local command_text='sudo -n /bin/bash -s --' argument
    for argument in "$@"; do
        [[ $argument =~ ^[A-Za-z0-9_./:-]+$ ]] || die 'Unsafe remote argument.'
        command_text+=" '$argument'"
    done
    timeout 45 ssh "${ssh_options[@]}" -p "$ssh_port" -T "$ssh_target" "$command_text" < "$worker"
}
state_started=0
finish() {
    local rc=$?
    trap - EXIT
    if [[ $state_started == 1 ]]; then
        remote_action logs "$run_id" > "$log_dir/remote.log" 2> "$log_dir/log-fetch-error.txt" || true
        printf 'Remote state/logs: /var/lib/systemvm-kernel-rollout/%s/\n' "$run_id"
    fi
    if (( rc != 0 )); then
        printf 'FAILED (exit %s). Remaining steps stopped. Local logs: %s\n' "$rc" "$log_dir" >&2
        if [[ -s $log_dir/remote.log ]]; then tail -n 45 "$log_dir/remote.log" >&2; fi
    fi
    exit "$rc"
}
trap finish EXIT

if [[ $mode != verify ]]; then
    printf '[1/8] Validating local archive, sidecar checksum and every tar member\n'
    metadata=$(python3 - "$archive_file" <<'PY'
from pathlib import Path, PurePosixPath
import hashlib, re, sys, tarfile
def sha256_stream(stream):
    # Python 3.9 (Rocky Linux 9) has no hashlib.file_digest (added in 3.11).
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(block)
    return digest.hexdigest()
archive=Path(sys.argv[1])
with archive.open('rb') as stream: digest=sha256_stream(stream)
match=re.fullmatch(r'([0-9a-f]{64}) [ *](.+)\n?',Path(str(archive)+'.sha256').read_text(encoding='utf-8'))
if not match or match[1]!=digest or match[2]!=archive.name: raise SystemExit('ERROR: archive sidecar checksum mismatch')
seen={}; root=None; manifest=None
with tarfile.open(archive,'r|gz') as tar:
    for entry in tar:
        path=PurePosixPath(entry.name)
        if path.is_absolute() or '..' in path.parts or any(c in entry.name for c in ('\\','\n','\r')):
            raise SystemExit('ERROR: unsafe archive path')
        if not path.parts or not re.fullmatch(r'debian12-kernel-amd64-[A-Za-z0-9_.-]+',path.parts[0]):
            raise SystemExit('ERROR: invalid bundle root')
        root=root or path.parts[0]
        if root!=path.parts[0] or not(entry.isdir() or entry.isfile()): raise SystemExit('ERROR: links/devices/multiple roots are rejected')
        if entry.isdir(): continue
        name=path.relative_to(root).as_posix()
        if name in seen or (name=='SHA256SUMS' and manifest is not None): raise SystemExit('ERROR: duplicate archive member')
        stream=tar.extractfile(entry)
        if name=='SHA256SUMS':
            if entry.size>4*1024*1024: raise SystemExit('ERROR: oversized manifest')
            manifest=stream.read().decode()
        else: seen[name]=sha256_stream(stream)
if manifest is None: raise SystemExit('ERROR: missing bundle checksum manifest')
expected={}
for line in manifest.splitlines():
    item=re.fullmatch(r'([0-9a-f]{64})  (?:\./)?(.+)',line)
    if not item or item[2] in expected: raise SystemExit('ERROR: invalid/duplicate checksum entry')
    expected[item[2]]=item[1]
for name in ('repo/lock','repo/partial/lock'):
    if name not in expected and seen.get(name)==hashlib.sha256(b'').hexdigest(): del seen[name]
if seen!=expected: raise SystemExit('ERROR: internal bundle checksums do not match')
required={'install-kernel.sh','kernel-boot-check.sh','kernel-package.txt','kernel-version.txt','meta-version.txt','cve-fixed-version.txt','roots.txt','repo/Packages','packages.tsv'}
if not required.issubset(seen) or not any(n.startswith('repo/') and n.endswith('.deb') for n in seen):
    raise SystemExit('ERROR: incomplete kernel bundle')
print(root); print(digest)
PY
    ) || die 'Local archive validation failed. Target was not contacted.'
    mapfile -t archive_metadata <<< "$metadata"
    bundle_name=${archive_metadata[0]} payload_digest=${archive_metadata[1]}
fi
printf '[2/8] Checking SSH, sudo and AbleStack VM identity (SystemVM/CKS)\n'
probe=$(remote_action probe) || die 'AbleStack VM/sudo/SSH preflight failed. No files transferred or packages installed.'
printf '%s\n' "$probe"
target_identity=$(awk -F= '$1=="SYSTEMVM_ID" {print $2}' <<< "$probe")
old_boot_id=$(awk -F= '$1=="SYSTEMVM_BOOT_ID" {print $2}' <<< "$probe")
target_role=$(awk -F= '$1=="SYSTEMVM_ROLE" {print $2}' <<< "$probe")
[[ $target_identity =~ ^[a-f0-9]{64}$ && $old_boot_id =~ ^[a-f0-9-]{36}$ ]] || die 'Invalid preflight response.'
if [[ $mode != verify ]]; then
    printf '[3/8] Uploading archive and worker as cloud using %s\n' "$transfer_protocol"
    result=$(remote_action upload-dir "$target_identity")
    upload_dir=$(awk -F= '$1=="UPLOAD_DIR" {print $2}' <<< "$result")
    [[ $upload_dir =~ ^/[A-Za-z0-9_./-]+/\.systemvm-kernel-upload\.[a-zA-Z0-9]{8}$ ]] || die 'Invalid upload directory response.'
    scp "${scp_protocol_options[@]}" "${ssh_options[@]}" -P "$ssh_port" -- "$archive_file" "$scp_target:$upload_dir/payload.tar.gz"
    scp "${scp_protocol_options[@]}" "${ssh_options[@]}" -P "$ssh_port" -- "$worker" "$scp_target:$upload_dir/worker.sh"
    worker_digest=$(sha256sum "$worker"); worker_digest=${worker_digest%% *}
    if [[ $mode == check ]]; then
        printf '[4/8] Starting detached root job: extract -> check (no install/reboot)\n'
    else
        printf '[4/8] Starting detached root job: extract -> check -> install -> check-boot\n'
    fi
    state_started=1
    remote_action prepare "$upload_dir" "$payload_digest" "$worker_digest" "$run_id" "$bundle_name" \
        "$target_identity" "$old_boot_id" "$mode" "$service_timeout"
    deadline=$((SECONDS + install_timeout))
    last_status=''
    while :; do
        if result=$(remote_action status "$run_id" 2> "$log_dir/last-ssh-error.txt"); then
            if [[ $result != "$last_status" ]]; then printf 'Remote phase: %s\n' "$result"; last_status=$result; fi
            case $result in
                COMPLETE_CHECK)
                    [[ $mode == check ]] || die 'Unexpected check-only result.'
                    printf 'SUCCESS: AbleStack VM check passed. No packages installed or reboot requested.\n'
                    exit 0 ;;
                REBOOT_PENDING) [[ $mode == apply ]] || die 'Unexpected reboot state.'; break ;;
                FAILED) die 'Remote worker failed. Inspect remote.log and the retained run directory.' ;;
                STARTING|EXTRACTING|CHECK|INSTALL|CHECK_BOOT) ;;
                *) die "Unexpected remote status: $result" ;;
            esac
        fi
        (( SECONDS < deadline )) || die 'Installer wait timed out. Root job may still be running; do not restart the rollout.'
        sleep 5
    done
    printf '[5/8] Waiting for reboot and SSH return (boot ID must change)\n'
    deadline=$((SECONDS + reboot_timeout))
    last_notice=$SECONDS
    while :; do
        new_boot_id=$(timeout 25 ssh "${ssh_options[@]}" -p "$ssh_port" -T "$ssh_target" 'cat /proc/sys/kernel/random/boot_id' 2> "$log_dir/last-ssh-error.txt") || new_boot_id=''
        if [[ $new_boot_id =~ ^[a-f0-9-]{36}$ && $new_boot_id != "$old_boot_id" ]]; then
            printf 'Reboot confirmed: %s -> %s\n' "$old_boot_id" "$new_boot_id"
            break
        fi
        if result=$(remote_action status "$run_id" 2> "$log_dir/last-ssh-error.txt"); then
            [[ $result != FAILED ]] || die 'Remote reboot request failed. Inspect remote.log; no second reboot was requested.'
        fi
        (( SECONDS < deadline )) || die 'Reboot/SSH wait timed out. No automatic reinstall or second reboot was requested.'
        if (( SECONDS - last_notice >= 30 )); then printf 'Waiting for a new boot ID and SSH...\n'; last_notice=$SECONDS; fi
        sleep 5
    done
else
    state_started=1
    printf 'Verify-only: using retained run %s; no transfer/install/reboot.\n' "$run_id"
fi
printf '[6/8] Verifying post-reboot AbleStack VM identity and running kernel\n'
printf '[7/8] Waiting for failed units=0 and required services to become active\n'
# Verification includes service startup waits; use a larger bound than status polling.
command_text="sudo -n /bin/bash -s -- verify '$run_id' '$service_timeout'"
timeout "$((service_timeout * 2 + 120))" ssh "${ssh_options[@]}" -p "$ssh_port" -T "$ssh_target" "$command_text" < "$worker"
printf '[8/8] SUCCESS: reboot, kernel and local service checks passed.\n'
if [[ $target_role == cksnode ]]; then
    printf 'Check Kubernetes Node Ready and workload/Pod health using cluster-admin kubectl separately.\n'
else
    printf 'Check AbleStack role functions (SSVM transfers / CPVM console / VR network) separately.\n'
fi
printf 'Local logs: %s\n' "$log_dir"
