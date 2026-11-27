#!/usr/bin/env bash
# Controller: SSH (cloud or sharedfs root) -> root worker -> check/install/check-boot -> reboot -> verify.
# Controller baseline: Rocky Linux 9, Bash 4.4+, Python 3.9+, openssh-clients.
# This script never copies the SSH private key to the target.
set -Eeuo pipefail
export LC_ALL=C
umask 077
rollout_revision=20261112-skip-service-health-11
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: bash deploy-systemvm-kernel.sh -k SSH_KEY -f PATCH.tar.gz -i TARGET_IP -p SSH_PORT [options]
       bash deploy-systemvm-kernel.sh -t sharedfs -f PATCH.tar.gz -i TARGET_IP [options]
       bash deploy-systemvm-kernel.sh -k SSH_KEY -i TARGET_IP -p SSH_PORT --verify-only RUN_ID
  -k, --key FILE         SSH private key file (ignored for sharedfs; used locally only)
  -t, --type TYPE        Target type (sharedfs allows omitting -k and -p)
  -f, --archive FILE     Kernel tar.gz (requires its adjacent .sha256)
  -i, --ip ADDRESS       Target VM IP address; sharedfs: root, otherwise: cloud
  -p, --port PORT        Target SSH port (sharedfs: prompt if omitted, default 22; otherwise required)
  --check-only            Identity, transfer, extraction and check; no install/reboot
  --verify-only RUN_ID    Recheck a previous apply run; no transfer/install/reboot
  --scp-legacy            Use legacy scp -O if target SFTP is unavailable
  --install-timeout SEC   Wait for detached installer (default: 1800)
  --reboot-timeout SEC    Wait for a different boot ID and SSH (default: 900)
  --service-timeout SEC   Wait for systemd/services after boot (default: 180)
  -h, --help             Show this help
Local logs: /var/lib/systemvm-kernel-rollout/ (write permission required).
Account: sharedfs uses root; otherwise cloud with passwordless sudo.
Sharedfs: prompt once for the root password; reuse via SSH_ASKPASS (no sshpass required).
Other types: key-based SSH is required.
Controller: Rocky Linux 9 (Python 3.9+, openssh-clients, coreutils, gawk).
Target: Debian 12 amd64 AbleStack SystemVM or SystemVM-template-based CKS node.
Default mode INSTALLS AND REBOOTS the target after successful checks.
HELP
    printf 'Revision: %s\n' "$rollout_revision"
}
[[ $# -gt 0 ]] || { usage >&2; exit 1; }
key_input='' target_ip='' ssh_port='' archive_input='' target_type=''
mode=apply resume_id='' scp_legacy=false
install_timeout=1800 reboot_timeout=900 service_timeout=180
while (( $# )); do
    case $1 in
        -k|--key|-t|--type|-f|--archive|-i|--ip|-p|--port|--verify-only|--install-timeout|--reboot-timeout|--service-timeout)
            [[ $# -ge 2 && -n $2 && $2 != -* ]] || die "Missing value for $1"
            case $1 in
                -k|--key) [[ -z $key_input ]] || die 'Duplicate option: -k/--key'; key_input=$2 ;;
                -t|--type) [[ -z $target_type ]] || die 'Duplicate option: -t/--type'; target_type=$2 ;;
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
[[ $target_type == sharedfs || -n $key_input ]] || die 'Required option missing: -k SSH_KEY (optional only with -t sharedfs)'
[[ -n $target_ip ]] || die 'Required option missing: -i TARGET_IP'
if [[ -z $ssh_port ]]; then
    [[ $target_type == sharedfs ]] || die 'Required option missing: -p SSH_PORT'
    printf 'Target SSH port [22]: ' > /dev/tty
    IFS= read -r ssh_port < /dev/tty || die 'Cannot read SSH port from the terminal; specify -p PORT.'
    ssh_port=${ssh_port:-22}
fi
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
if [[ $target_type != sharedfs && -n $key_input ]]; then
    key_file=$(realpath -- "$key_input")
    [[ -f $key_file && -r $key_file ]] || die 'SSH key file is not readable.'
fi
if [[ $mode != verify ]]; then
    archive_file=$(realpath -- "$archive_input")
    [[ -f $archive_file && -f $archive_file.sha256 ]] || die 'Archive and adjacent .tar.gz.sha256 are required.'
fi
[[ $mode != verify || $resume_id =~ ^[0-9]{8}T[0-9]{6}Z-[a-zA-Z0-9]{8}$ ]] || die 'Invalid RUN_ID.'
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(mktemp -u XXXXXXXX)"
[[ $mode != verify ]] || run_id=$resume_id
ssh_user=cloud
remote_shell='sudo -n /bin/bash -s --'
if [[ $target_type == sharedfs ]]; then
    ssh_user=root
    remote_shell='/bin/bash -s --'
fi
log_base=/var/lib/systemvm-kernel-rollout
mkdir -p -- "$log_base" || die "Cannot create log directory: $log_base. Run with write permission to this directory."
# Numeric IP was validated above; replace IPv6 colons for a readable path component.
log_target=${target_ip//:/_}
log_dir=$(mktemp -d "$log_base/systemvm-rollout-${run_id%%-*}-$log_target-port-$ssh_port-${run_id#*-}-XXXXXXXX") ||
    die "Cannot create run logs under $log_base. Run with write permission to this directory."
worker="$log_dir/remote-worker.sh"
exec > >(tee "$log_dir/controller.log") 2>&1
printf 'Mode: %s | Target: %s@%s:%s | Run: %s\nLocal logs: %s\n' "$mode" "$ssh_user" "$target_ip" "$ssh_port" "$run_id" "$log_dir"
printf 'Revision: %s\n' "$rollout_revision"
printf 'Controller Python: %s\n' "$(python3 --version 2>&1)"
scp_protocol_options=()
transfer_protocol='SFTP (scp default on Rocky Linux 9)'
if [[ $scp_legacy == true ]]; then
    scp_protocol_options=(-O)
    transfer_protocol='legacy SCP (-O, explicitly requested)'
fi
ssh_options=(-o ForwardAgent=no
    -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no
    -o ControlMaster=no -o ControlPath=none -o ConnectTimeout=10 -o ConnectionAttempts=1
    -o ServerAliveInterval=10 -o ServerAliveCountMax=2 -o LogLevel=ERROR)
if [[ $target_type == sharedfs ]]; then
    ssh_options+=(-o BatchMode=no -o PreferredAuthentications=password
        -o PubkeyAuthentication=no -o PasswordAuthentication=yes
        -o KbdInteractiveAuthentication=no -o NumberOfPasswordPrompts=3)
else
    ssh_options+=(-o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no)
fi
if [[ $target_type != sharedfs && -n $key_input ]]; then
    ssh_options=(-i "$key_file" -o IdentitiesOnly=yes "${ssh_options[@]}")
fi
ssh_target="$ssh_user@$target_ip"
scp_target=$ssh_target
[[ $target_ip != *:* ]] || scp_target="$ssh_user@[$target_ip]"

# Standalone Bash worker, copied without credentials and installed root-owned.
printf '#!/usr/bin/env bash\nrollout_account=%q\n' "$ssh_user" > "$worker"
cat >> "$worker" <<'REMOTE'
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
    # Some supported CKS templates do not ship /etc/ablestack-release.
    # Require the template setup script and role cache, then validate role below.
    [[ -s /opt/cloud/bin/setup/common.sh && -s /var/cache/cloud/cmdline ]] ||
        die 'Template setup script or role cache missing/empty (/opt/cloud/bin/setup/common.sh, /var/cache/cloud/cmdline). No transfer/install/reboot is permitted.'
    # Never source or print cmdline: it can contain credentials and private keys.
    role=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^type=/) {sub(/^type=/,"",$i); print $i}}' /var/cache/cloud/cmdline)
    [[ -n $role ]] || die 'AbleStack type= marker is missing.'
    [[ $role != *$'\n'* ]] || die 'Multiple AbleStack type= markers found; review the target identity.'
    vm_class=systemvm
    cks_primary_unit=''
    case $role in
        router|vpcrouter|dhcpsrvr|secstorage|consoleproxy|internallbvm) ;;
        sharedfs|sharedfsvm)
            [[ $rollout_account == root ]] || die 'Shared storage VM requires -t sharedfs.'
            vm_class=sharedfs
            ;;
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
        *)
            printf 'Detected unsupported AbleStack role: %q\n' "$role" >&2
            die 'Unsupported AbleStack VM type; supported targets include SystemVM, CKS and sharedfs.'
            ;;
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
# Keep this block identical in the standalone remote worker and bundle helper.
grub_enable_recovery_menu() {
    local kind=$1 config=$2 release=$3 backup defaults=/etc/default/grub
    local drop_dir=/etc/default/grub.d drop_file candidate
    backup=$(mktemp -d "$(dirname -- "$config")/kernel-menu-backup.XXXXXXXX") || return 1
    cp -p -- "$config" "$backup/" || return 1
    printf 'GRUB recovery menu backup: %s\n' "$backup"
    if [[ $kind == grub2 ]]; then
        [[ -f $defaults && -r $defaults ]] || {
            grub_error 'Missing /etc/default/grub; cannot configure recovery menu.'; return 1;
        }
        cp -p -- "$defaults" "$backup/default-grub" || return 1
        mkdir -p -- "$drop_dir" || return 1
        drop_file="$drop_dir/zzzz-systemvm-kernel-menu.cfg"
        if [[ -e $drop_file || -L $drop_file ]]; then
            [[ -f $drop_file && ! -L $drop_file ]] || {
                grub_error 'Managed GRUB menu drop-in must be a regular file.'; return 1;
            }
            cp -p -- "$drop_file" "$backup/menu-drop-in.cfg" || return 1
        fi
        candidate=$(mktemp "$drop_dir/.kernel-menu.XXXXXXXX") || return 1
        cat > "$candidate" <<'MENU'
# Managed by the offline SystemVM kernel installer.
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
GRUB_RECORDFAIL_TIMEOUT=10
MENU
        chmod 0644 "$candidate" || return 1
        mv -f -- "$candidate" "$drop_file" || return 1
        # Inspect the same ordering used by Debian grub-mkconfig. A later
        # site-specific override must not silently hide the recovery menu.
        if ! /bin/sh -c '
            . /etc/default/grub
            for f in /etc/default/grub.d/*.cfg; do
                [ ! -e "$f" ] || . "$f" || exit 1
            done
            [ "$GRUB_TIMEOUT_STYLE" = menu ] && [ "$GRUB_TIMEOUT" = 10 ] &&
                [ "$GRUB_RECORDFAIL_TIMEOUT" = 10 ]
        '; then
            grub_error "GRUB menu settings are overridden or invalid; review $drop_dir. Backup: $backup. Do not reboot."
            return 1
        fi
    fi
    grub_update_config_set "$kind" "$config" "$release" || return 1
    if [[ $kind == legacy ]]; then
        candidate=$(mktemp "$(dirname -- "$config")/.kernel-menu.XXXXXXXX") || return 1
        # Preserve updater metadata comments, including Debian automagic options.
        awk '
            /^[[:space:]]*timeout[[:space:]=]/ {next}
            /^[[:space:]]*hiddenmenu([[:space:]]|$)/ {next}
            BEGIN {print "timeout 10"}
            {print}
        ' "$config" > "$candidate" || return 1
        chmod --reference="$config" "$candidate" || return 1
        mv -f -- "$candidate" "$config" || return 1
    fi
    grub_validate_recovery_menu "$kind" "$config" || return 1
    printf 'GRUB recovery menu enabled: 10 seconds. Select an installed previous kernel using the VM console.\n'
}

grub_validate_recovery_menu() {
    local kind=$1 config=$2
    if ! awk -v kind="$kind" '
        /^[[:space:]]*#/ {next}
        kind=="legacy" && $1=="hiddenmenu" {bad=1}
        kind=="legacy" && $1=="timeout" {seen++; if ($2!="10") bad=1}
        kind=="grub2" && $1=="set" && $2 ~ /^timeout_style=/ {
            style=$2; gsub(/[\042\047]/,"",style)
            if (style!="timeout_style=menu") bad=1
            menu++
        }
        kind=="grub2" && $1=="set" && $2 ~ /^timeout=/ {
            value=$2; gsub(/[\042\047]/,"",value)
            if (value!="timeout=10") bad=1
            seen++
        }
        END {exit (bad || !seen || (kind=="grub2" && !menu)) ? 1 : 0}
    ' "$config"; then
        grub_error "Cannot verify a visible 10-second menu in $config. Do not reboot."
        return 1
    fi
}
# End shared recovery menu block.

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
        upload_home=$(getent passwd "$rollout_account" | cut -d: -f6)
        [[ $upload_home =~ ^/[A-Za-z0-9_./-]+$ ]] || die 'Unsupported upload account home path.'
        upload=$(mktemp -d "$upload_home/.systemvm-kernel-upload.XXXXXXXX")
        chown "$rollout_account" -- "$upload"
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
        upload_home=$(getent passwd "$rollout_account" | cut -d: -f6)
        [[ $upload == "$upload_home"/.systemvm-kernel-upload.* && ${upload##*/} =~ ^\.systemvm-kernel-upload\.[a-zA-Z0-9]{8}$ && ! -L $upload ]] || die 'Invalid upload path.'
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
        phase=GRUB_MENU; status_write "$phase"
        # Works with existing verified archives as well as newly built bundles.
        # The helper functions run in this worker, outside the archive installer.
        source "$bundle/kernel-boot-check.sh"
        grub_detect
        kernel_release=$(cat "$bundle/kernel-package.txt")
        kernel_release=${kernel_release#linux-image-}
        grub_enable_recovery_menu "$grub_kind" "$grub_config" "$kernel_release"
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
        printf 'Updated kernel version: %s\n' "$(uname -r)"
        cat /proc/version
        printf 'CA certificates package version: '
        dpkg-query -W -f='${Version}\n' ca-certificates
        status_write VERIFIED
        printf 'Kernel and reboot verified. Service health checks skipped; validate role functions separately.\n'
        ;;
    logs)
        state_for "$1"
        for file in error.txt run.log verify.log; do
            if [[ -f $state/$file ]]; then printf '\n--- %s ---\n' "$file"; cat "$state/$file"; fi
        done
        ;;
    *) die 'Invalid worker action.' ;;
esac
REMOTE

remote_action() {
    local command_text="$remote_shell" argument
    for argument in "$@"; do
        [[ $argument =~ ^[A-Za-z0-9_./:-]+$ ]] || die 'Unsafe remote argument.'
        command_text+=" '$argument'"
    done
    timeout --foreground 45 ssh "${ssh_options[@]}" -p "$ssh_port" -T "$ssh_target" "$command_text" < "$worker"
}
state_started=0
auth_dir=''
cleanup_auth() {
    if [[ -n $auth_dir ]]; then
        rm -f -- "$auth_dir/askpass" "$auth_dir/askpass.password"
        rmdir -- "$auth_dir"
    fi
}
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
    cleanup_auth
    exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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
if [[ $target_type == sharedfs ]]; then
    # OpenSSH closes inherited descriptors before askpass. Keep its secret in a
    # private temporary directory outside rollout logs, removed by the EXIT trap.
    set +x
    sharedfs_password=''
    printf 'Root SSH password for %s: ' "$target_ip" > /dev/tty
    if ! IFS= read -r -s sharedfs_password < /dev/tty; then
        printf '\n' > /dev/tty
        die 'Cannot read root SSH password from the terminal.'
    fi
    printf '\n' > /dev/tty
    [[ -n $sharedfs_password ]] || die 'Root SSH password must not be empty.'
    auth_dir=$(mktemp -d /tmp/systemvm-ssh-auth.XXXXXXXX)
    chmod 0700 "$auth_dir"
    printf '%s\n' "$sharedfs_password" > "$auth_dir/askpass.password"
    chmod 0600 "$auth_dir/askpass.password"
    unset sharedfs_password
    cat > "$auth_dir/askpass" <<'ASKPASS'
#!/bin/sh
cat -- "$0.password"
ASKPASS
    chmod 0700 "$auth_dir/askpass"
    export SSH_ASKPASS="$auth_dir/askpass"
    export SSH_ASKPASS_REQUIRE=force
    export DISPLAY="${DISPLAY:-systemvm-askpass}"
fi
printf '[2/8] Checking SSH, sudo and AbleStack VM identity (SystemVM/CKS)\n'
if probe=$(remote_action probe 2> "$log_dir/preflight-error.txt"); then
    :
else
    preflight_rc=$?
    printf 'Preflight failed (exit %s). Target: %s:%s\n' "$preflight_rc" "$ssh_target" "$ssh_port" >&2
    [[ ! -s $log_dir/preflight-error.txt ]] || cat "$log_dir/preflight-error.txt" >&2
    [[ -z $probe ]] || printf '%s\n' "$probe" >&2
    [[ $preflight_rc != 124 ]] || printf 'SSH/preflight timed out after 45 seconds (including password entry).\n' >&2
    die 'AbleStack VM/sudo/SSH preflight failed. No files transferred or packages installed.'
fi
printf '%s\n' "$probe"
target_identity=$(awk -F= '$1=="SYSTEMVM_ID" {print $2}' <<< "$probe")
old_boot_id=$(awk -F= '$1=="SYSTEMVM_BOOT_ID" {print $2}' <<< "$probe")
target_role=$(awk -F= '$1=="SYSTEMVM_ROLE" {print $2}' <<< "$probe")
[[ $target_identity =~ ^[a-f0-9]{64}$ && $old_boot_id =~ ^[a-f0-9-]{36}$ ]] || die 'Invalid preflight response.'
if [[ $mode != verify ]]; then
    printf '[3/8] Uploading archive and worker as %s using %s\n' "$ssh_user" "$transfer_protocol"
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
                STARTING|EXTRACTING|CHECK|INSTALL|GRUB_MENU|CHECK_BOOT) ;;
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
        new_boot_id=$(timeout --foreground 25 ssh "${ssh_options[@]}" -p "$ssh_port" -T "$ssh_target" 'cat /proc/sys/kernel/random/boot_id' 2> "$log_dir/last-ssh-error.txt") || new_boot_id=''
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
printf '[7/8] Service health checks skipped\n'
# Verification includes service startup waits; use a larger bound than status polling.
command_text="$remote_shell verify '$run_id' '$service_timeout'"
timeout --foreground "$((service_timeout * 2 + 120))" ssh "${ssh_options[@]}" -p "$ssh_port" -T "$ssh_target" "$command_text" < "$worker"
printf '[8/8] SUCCESS: reboot and kernel checks passed.\n'
if [[ $target_role == sharedfs || $target_role == sharedfsvm ]]; then
    printf 'Check shared storage services, client mounts and volume read/write access separately.\n'
elif [[ $target_role == cksnode ]]; then
    printf 'Check Kubernetes Node Ready and workload/Pod health using cluster-admin kubectl separately.\n'
else
    printf 'Check AbleStack role functions (SSVM transfers / CPVM console / VR network) separately.\n'
fi
printf 'Local logs: %s\n' "$log_dir"
