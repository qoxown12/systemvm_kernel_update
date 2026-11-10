#!/usr/bin/env bash
# GRUB inspection and guarded updates. Standalone modes are read-only.
# Prefer the validated existing GRUB2 config, independently of leftover tools.
# Actual execution of the selected kernel is verified after reboot.
grub_boot_revision=20261106-grub2-primary-3
grub_error() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

grub_detect() {
    local updater=${1:-} grub_dir=${2:-/boot/grub} existing_release
    # Select the existing configuration first. A leftover update-grub binary
    # must not turn a healthy GRUB2 setup into a Legacy requirement.
    if [[ -e $grub_dir/grub.cfg || -L $grub_dir/grub.cfg ]]; then
        [[ -s $grub_dir/grub.cfg ]] || {
            grub_error 'Existing GRUB2 configuration is empty/missing; review the boot setup.'; return 1;
        }
        command -v grub-mkconfig >/dev/null && command -v grub-script-check >/dev/null || {
            grub_error 'grub-mkconfig and grub-script-check are required for the existing GRUB2 configuration.'; return 1;
        }
        existing_release=$(awk '
            $1=="linux" || $1=="linuxefi" || $1=="linux16" {
                path=$2; sub(/^.*\//,"",path)
                if(path ~ /^vmlinuz-[0-9][A-Za-z0-9.+~_-]*$/) {sub(/^vmlinuz-/,"",path); print path; exit}
            }' "$grub_dir/grub.cfg")
        [[ -n $existing_release ]] || {
            grub_error 'Existing grub.cfg has no recognizable Linux entry; manual boot review is required.'; return 1;
        }
        grub_validate_entry grub2 "$grub_dir/grub.cfg" "$existing_release" || return 1
        grub_kind=grub2
        grub_config="$grub_dir/grub.cfg"
        grub_updater=$(command -v grub-mkconfig)
    else
        # Compatibility for an actual Legacy-only layout. Not used by GRUB2.
        [[ -n $updater ]] || updater=$(command -v update-grub) || {
            grub_error 'No GRUB2 configuration or recognized boot updater is available.'; return 1;
        }
        updater=$(readlink -f -- "$updater") || return 1
        [[ -r $updater && -f $updater && -x $updater ]] || {
            grub_error "Cannot inspect GRUB updater: $updater"; return 1;
        }
        if ! grep -Fq 'menu.lst' "$updater" || grep -Eq '^[^#]*grub-mkconfig' "$updater"; then
            grub_error "Unrecognized updater or missing GRUB2 configuration: $updater. Review the boot setup."
            return 1
        fi
        grub_kind=legacy
        grub_config="$grub_dir/menu.lst"
        grub_updater=$updater
        [[ -s $grub_config ]] || {
            grub_error "GRUB configuration is missing/empty: $grub_config. Review the boot setup."; return 1;
        }
    fi
    printf 'GRUB configuration strategy: %s\nGRUB configuration: %s\nGRUB generator: %s\n' "$grub_kind" "$grub_config" "$grub_updater"
}

grub_validate_entry() {
    local kind=$1 config=$2 release=$3 wanted_entry=${4:--1}
    [[ $kind == legacy || $kind == grub2 ]] || { grub_error 'Unknown GRUB type.'; return 1; }
    [[ -s $config ]] || { grub_error "Missing GRUB configuration: $config"; return 1; }
    # Match uncommented kernel and matching initrd in the SAME menu entry.
    # A version appearing only in a title/comment or another entry is not proof.
    if ! awk -v kind="$kind" -v release="$release" -v wanted="$wanted_entry" '
        function finish() {
            if (active && kernel_ok && initrd_ok && (wanted<0 || ordinal==wanted)) {
                if (!found) print "Validated entry: " title
                found=1
            }
            active=0; kernel_ok=0; initrd_ok=0
        }
        function basename(path) { sub(/^.*\//, "", path); return path }
        /^[[:space:]]*#/ { next }
        {
            if ((kind=="legacy" && $1=="title") || (kind=="grub2" && $1=="menuentry")) {
                finish(); active=1; title=$0; entry_depth=depth+1; ordinal=entry_count++
            }
            if (active && ((kind=="legacy" && $1=="kernel") ||
                (kind=="grub2" && ($1=="linux" || $1=="linuxefi" || $1=="linux16")))) {
                kernel_ok=(basename($2)=="vmlinuz-" release)
            }
            if (active && ($1=="initrd" || (kind=="grub2" && ($1=="initrdefi" || $1=="initrd16")))) {
                initrd_ok=0
                for (i=2; i<=NF; i++) if (basename($i)=="initrd.img-" release) initrd_ok=1
            }
            if (kind=="grub2") {
                line=$0; opens=gsub(/\{/, "{", line)
                line=$0; closes=gsub(/\}/, "}", line)
                depth+=opens-closes
                if (active && depth<entry_depth) finish()
            }
        }
        END { finish(); exit(found ? 0 : 1) }
    ' "$config"; then
        grub_error "No complete kernel/initrd entry for $release in $config. Do not reboot."
        return 1
    fi
    # grub-script-check parses GRUB2 syntax; never run it against Legacy menu.lst.
    if [[ $kind == grub2 ]] && command -v grub-script-check >/dev/null; then
        grub-script-check "$config" || {
            grub_error 'GRUB2 syntax check failed. Do not reboot.'; return 1;
        }
    fi
}

grub_validate_selection() {
    local kind=$1 config=$2 release=$3 value defaults raw has_zero=false uses_next=false env_text next
    if [[ $kind == legacy ]]; then
        value=$(awk '$1=="default" {value=$2; count++} END {if(count>1) exit 1; print(count ? value : "0")}' "$config") || {
            grub_error "Ambiguous default directives in $config. Review boot selection."; return 1;
        }
        [[ $value == 0 ]] || {
            grub_error "Legacy default=$value in $config requires manual selection review for $release."; return 1;
        }
    else
        defaults=$(awk '$1=="set" && $2 ~ /^default=/ {sub(/^default=/,"",$2); print $2}' "$config")
        while IFS= read -r raw; do
            value=${raw#\"}; value=${value%\"}
            value=${value#\'}; value=${value%\'}
            case $value in
                0) has_zero=true ;;
                '${next_entry}'|'$next_entry') uses_next=true ;;
                *) grub_error "GRUB2 default=$value in $config requires manual selection review for $release."; return 1 ;;
            esac
        done <<< "$defaults"
        [[ $has_zero == true ]] || {
            grub_error "No verifiable default=0 in $config. Review the saved/explicit boot selection."; return 1;
        }
        if [[ $uses_next == true && -s $(dirname -- "$config")/grubenv ]]; then
            command -v grub-editenv >/dev/null || { grub_error 'Cannot inspect GRUB2 next_entry without grub-editenv.'; return 1; }
            env_text=$(grub-editenv "$(dirname -- "$config")/grubenv" list) || return 1
            next=$(awk -F= '$1=="next_entry" {sub(/^[^=]*=/,""); print}' <<< "$env_text")
            [[ -z $next ]] || {
                grub_error "GRUB2 next_entry=$next overrides default=0. Review it explicitly before rebooting."; return 1;
            }
        fi
    fi
    grub_validate_entry "$kind" "$config" "$release" 0 || {
        grub_error "Default first entry in $config does not boot $release with matching initrd. Do not reboot."; return 1;
    }
}

grub_validate_config_set() {
    local kind=$1 config=$2 release=$3
    # Only the selected configuration determines readiness. In GRUB2 mode,
    # an unused Legacy file must not create a requirement or block the update.
    grub_validate_entry "$kind" "$config" "$release" || return 1
    grub_validate_selection "$kind" "$config" "$release"
}

grub_require_update_tools() {
    local kind=$1 config=$2 grub_dir
    grub_dir=$(dirname -- "$config")
    [[ -w $config && -w $grub_dir ]] || {
        grub_error "GRUB configuration directory is not writable: $grub_dir"; return 1;
    }
    if [[ $kind == grub2 ]]; then
        command -v grub-mkconfig >/dev/null && command -v grub-script-check >/dev/null || {
            grub_error 'grub-mkconfig and grub-script-check are required to update the existing GRUB2 configuration.'
            return 1
        }
    fi
}

grub_update_config_set() {
    local kind=$1 config=$2 release=$3 grub_dir backup candidate
    grub_require_update_tools "$kind" "$config" || return 1
    grub_dir=$(dirname -- "$config")
    backup=$(mktemp -d "$grub_dir/kernel-offline-backup.XXXXXXXX") || return 1
    cp -p -- "$config" "$backup/" || return 1
    printf 'GRUB config backup: %s\n' "$backup"
    # Legacy uses its inspected updater; GRUB2 is generated directly below.
    # Never reinstall a bootloader or touch MBR/EFI.
    if [[ $kind == legacy ]]; then
        "$grub_updater" || return 1
    fi
    if [[ $kind == grub2 ]]; then
        candidate=$(mktemp "$grub_dir/.kernel-offline-grub2.XXXXXXXX") || return 1
        printf 'Regenerating existing GRUB2 configuration: %s/grub.cfg\n' "$grub_dir"
        if ! grub-mkconfig -o "$candidate"; then
            grub_error "GRUB2 generation failed. Original grub.cfg retained; candidate: $candidate"; return 1
        fi
        if ! grub_validate_entry grub2 "$candidate" "$release"; then
            grub_error "Generated GRUB2 candidate rejected. Original grub.cfg retained; candidate: $candidate"; return 1
        fi
        if ! grub_validate_selection grub2 "$candidate" "$release"; then
            grub_error "Generated GRUB2 selection requires review. Original grub.cfg retained; candidate: $candidate"; return 1
        fi
        chmod --reference="$grub_dir/grub.cfg" "$candidate" || return 1
        mv -- "$candidate" "$grub_dir/grub.cfg" || return 1
    fi
    grub_validate_config_set "$kind" "$config" "$release"
}

grub_show_selection() {
    local kind=$1 config=$2 grub_dir
    grub_dir=$(dirname -- "$config")
    printf 'Boot selection settings (review with the hypervisor console):\n'
    if [[ $kind == legacy ]]; then
        awk '$1=="default" || $1=="fallback" {print}' "$config"
    else
        awk '/^[[:space:]]*set[[:space:]]+default=/ {print}' "$config"
    fi
    if [[ $kind == grub2 && -s $grub_dir/grubenv ]] && command -v grub-editenv >/dev/null; then
        printf 'GRUB2 environment (review next_entry/saved_entry if used by the config):\n'
        grub-editenv "$grub_dir/grubenv" list || return 1
    fi
    printf 'Entry validation does not identify the bootloader installed in the disk/firmware or a hypervisor-selected kernel.\n'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -Eeuo pipefail
    export LC_ALL=C
    mode=${1:-}
    release=${2:-}
    [[ $# -eq 2 && ( $mode == preflight || $mode == check ) && $release =~ ^6\.1\.0-[0-9]+-amd64$ ]] || {
        printf 'Usage: bash %s preflight|check KERNEL-RELEASE\n' "$0" >&2; exit 1;
    }
    grub_detect
    if [[ $mode == check ]]; then
        [[ -s /boot/vmlinuz-$release && -s /boot/initrd.img-$release && -d /lib/modules/$release ]] || {
            grub_error 'Kernel/initramfs/modules missing. Do not reboot.'; exit 1;
        }
        grub_validate_config_set "$grub_kind" "$grub_config" "$release"
        grub_show_selection "$grub_kind" "$grub_config"
        printf 'Boot entry check passed. No packages installed, no boot configuration changed, no reboot performed.\n'
    fi
fi
