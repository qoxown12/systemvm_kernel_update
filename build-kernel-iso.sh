#!/usr/bin/env bash
# Wrap an authenticated, checksummed kernel tar.gz in a mount-and-run data ISO.
set -Eeuo pipefail
export LC_ALL=C
umask 022
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf 'Usage: bash %s KERNEL-BUNDLE.tar.gz [OUTPUT.iso]\n' "$0"
    printf 'Requires genisoimage, isoinfo and python3 on the builder only.\n'
    exit 0
fi
[[ $# -ge 1 && $# -le 2 ]] || die "Usage: bash $0 KERNEL-BUNDLE.tar.gz [OUTPUT.iso]"
for cmd in genisoimage isoinfo python3 realpath sha256sum; do
    command -v "$cmd" >/dev/null || die "Missing $cmd. Install genisoimage and python3 on the online builder."
done
archive=$(realpath -- "$1")
[[ -f $archive && $archive == *.tar.gz ]] || die 'Input must be a kernel bundle .tar.gz file.'
output=${2:-${archive%.tar.gz}.iso}
output=$(realpath -m -- "$output")
[[ $output == *.iso && ! -e $output && ! -e $output.sha256 ]] || die 'Choose a new .iso output path; existing artifacts are not overwritten.'
mkdir -p -- "$(dirname -- "$output")"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ -r $script_dir/run-kernel-from-iso.sh ]] || die 'Keep run-kernel-from-iso.sh beside this script.'
work_dir=$(mktemp -d "$(dirname -- "$output")/.iso-build.XXXXXXXX")
stage="$work_dir/media"
mkdir -p "$stage/payload" "$stage/source"
cleanup() {
    rc=$?
    if [[ $rc -eq 0 && ${KERNEL_ISO_KEEP_STAGE:-0} != 1 ]]; then
        rm -rf -- "$work_dir"
    else
        printf 'ISO build workspace: %s\n' "$work_dir" >&2
    fi
    exit "$rc"
}
trap cleanup EXIT
printf '[1/3] Validating the tar payload and staging ISO files\n'
python3 - "$archive" "$stage" <<'PY'
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile

archive, stage = map(Path, sys.argv[1:])
with archive.open('rb') as stream:
    input_digest = hashlib.file_digest(stream, 'sha256').hexdigest()
root = None
seen = {}
metadata = {}
manifest = None
with tarfile.open(archive, 'r|gz') as tar:
    for entry in tar:
        path = PurePosixPath(entry.name)
        if path.is_absolute() or '..' in path.parts or '\\' in entry.name or '\n' in entry.name or '\r' in entry.name:
            raise SystemExit('ERROR: unsafe tar member path')
        if not path.parts or not re.fullmatch(r'debian12-kernel-amd64-[A-Za-z0-9_.-]+', path.parts[0]):
            raise SystemExit('ERROR: expected one Debian 12 amd64 bundle root')
        root = root or path.parts[0]
        if path.parts[0] != root or not (entry.isdir() or entry.isfile()):
            raise SystemExit('ERROR: multiple roots or unsupported tar member type (links/devices are rejected)')
        if entry.isdir():
            continue
        relative = path.relative_to(root).as_posix()
        if relative in seen or (relative == 'SHA256SUMS' and manifest is not None):
            raise SystemExit('ERROR: duplicate tar member')
        stream = tar.extractfile(entry)
        if relative == 'SHA256SUMS':
            if entry.size > 4 * 1024 * 1024:
                raise SystemExit('ERROR: oversized checksum manifest')
            manifest = stream.read()
        elif relative in {'kernel-package.txt', 'kernel-version.txt', 'meta-version.txt'}:
            data = stream.read()
            metadata[relative] = data
            seen[relative] = hashlib.sha256(data).hexdigest()
        else:
            seen[relative] = hashlib.file_digest(stream, 'sha256').hexdigest()
if manifest is None:
    raise SystemExit('ERROR: bundle SHA256SUMS is missing')
expected = {}
for line in manifest.decode().splitlines():
    match = re.fullmatch(r'([0-9a-f]{64})  (?:\./)?(.+)', line)
    if not match:
        raise SystemExit('ERROR: invalid checksum manifest')
    digest, name = match.groups()
    if name in expected:
        raise SystemExit('ERROR: duplicate checksum entry')
    expected[name] = digest
# Old APT build archives can contain unprotected lock files; admit only empty
# lock files, never any other unprotected member (including user-added secrets).
empty_hash = hashlib.sha256(b'').hexdigest()
for name in list(seen):
    if name not in expected and name in {'repo/lock', 'repo/partial/lock'} and seen[name] == empty_hash:
        del seen[name]
if expected != seen:
    raise SystemExit('ERROR: bundle file checksums do not match; rebuild a clean tar bundle')
required = {'install-kernel.sh', 'kernel-boot-check.sh', 'repo/Packages', 'packages.tsv',
            'kernel-package.txt', 'kernel-version.txt', 'meta-version.txt', 'roots.txt', 'cve-fixed-version.txt'}
if not required.issubset(seen) or not any(p.startswith('repo/') and p.endswith('.deb') for p in seen):
    raise SystemExit('ERROR: not a complete offline kernel bundle')
canonical = root + '.tar.gz'
dest = stage / 'payload' / canonical
try:
    os.link(archive, dest)
except OSError:
    shutil.copyfile(archive, dest)
with dest.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
if digest != input_digest:
    raise SystemExit('ERROR: input archive changed during the build')
(stage / 'bundle-name.txt').write_text(root + '\n')
(stage / 'payload-file.txt').write_text(canonical + '\n')
(stage / 'payload-sha256.txt').write_text(digest + '\n')
(stage / 'payload-SHA256SUMS').write_bytes(manifest)
for name, data in metadata.items():
    (stage / name).write_bytes(data)
print(f'Validated payload: {root}; {sum(p.endswith(".deb") for p in seen)} Debian packages')
PY
cp -- "$script_dir/run-kernel-from-iso.sh" "$stage/install-kernel.sh"
cp -- "$script_dir/build-kernel-iso.sh" "$script_dir/run-kernel-from-iso.sh" "$stage/source/"
chmod 0755 "$stage/install-kernel.sh"
for doc in BUILD.md INSTALL.md plan.md; do
    if [[ -f $script_dir/$doc ]]; then cp -- "$script_dir/$doc" "$stage/$doc"; fi
done
cat > "$stage/README-ISO-KO.txt" <<'README'
Debian 12 amd64 커널 업데이트 데이터 ISO

VM에 CD/DVD로 연결하고 root에서 실제 CD 장치(예: /dev/sr0)를 마운트합니다.
  mkdir -p /mnt/kernel-offline
  mount -t iso9660 -o ro /dev/sr0 /mnt/kernel-offline
  bash /mnt/kernel-offline/install-kernel.sh check
점검 통과 후:
  bash /mnt/kernel-offline/install-kernel.sh install
  bash /mnt/kernel-offline/install-kernel.sh check-boot
부팅 선택과 복구 방법을 확인한 뒤 점검 시간에 직접 재부팅합니다.
재접속 후 ISO를 다시 마운트하지 않고도 실행할 수 있습니다.
  bash /var/lib/systemvm-kernel-offline/current/install-kernel.sh verify
  uname -r
  systemctl --failed

실행기가 무결성을 확인한 뒤 VM의 /var/lib/systemvm-kernel-offline에
묶음을 자동 준비하고 기존 설치기를 실행합니다. 사용자의 수동 압축 해제는
필요하지 않습니다. ISO에는 쓰지 않으며 패키지 설치와 자동 재부팅을
사용자 요청 없이 수행하지 않습니다. check는 패키지를 설치하지 않습니다.
로그: /var/lib/systemvm-kernel-offline/current/logs/
데이터 ISO이므로 운영체제를 새로 설치하는 부팅용 ISO가 아닙니다.
README
python3 - "$stage" <<'PY'
from pathlib import Path
import hashlib
import sys
stage = Path(sys.argv[1])
lines = []
for path in sorted(stage.rglob('*')):
    if path.is_file() and path.name != 'SHA256SUMS':
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        lines.append(f'{digest}  ./{path.relative_to(stage).as_posix()}\n')
(stage / 'SHA256SUMS').write_text(''.join(lines))
PY
printf '[2/3] Creating Rock Ridge/Joliet data ISO\n'
genisoimage -quiet -R -J -joliet-long -iso-level 3 -input-charset utf-8 \
    -V DEB12_KERNEL -o "$output.partial" "$stage" > "$work_dir/genisoimage.log" 2>&1 || {
    cat "$work_dir/genisoimage.log" >&2; die 'ISO creation failed.';
}
printf '[3/3] Reading back every ISO file and comparing SHA256\n'
python3 - "$stage" "$output.partial" <<'PY'
from pathlib import Path
import hashlib
import subprocess
import sys
stage, iso = map(Path, sys.argv[1:])
count = 0
for path in sorted(stage.rglob('*')):
    if not path.is_file():
        continue
    with path.open('rb') as stream:
        expected = hashlib.file_digest(stream, 'sha256').hexdigest()
    relative = '/' + path.relative_to(stage).as_posix()
    proc = subprocess.Popen(['isoinfo', '-R', '-i', str(iso), '-x', relative], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    actual = hashlib.file_digest(proc.stdout, 'sha256').hexdigest()
    error = proc.stderr.read()
    if proc.wait() or actual != expected:
        raise SystemExit(f'ERROR: ISO read-back mismatch for {relative}: {error.decode(errors="replace")}')
    count += 1
print(f'ISO read-back verified: {count} files, including the complete tar payload')
PY
mv -- "$output.partial" "$output"
(cd -- "$(dirname -- "$output")" && sha256sum "$(basename -- "$output")" > "$(basename -- "$output").sha256")
printf '\nSUCCESS\nISO: %s\nChecksum: %s.sha256\n' "$output" "$output"
printf 'Attach as a virtual CD/DVD, mount read-only, then run: bash /mnt/kernel-offline/install-kernel.sh check\n'
