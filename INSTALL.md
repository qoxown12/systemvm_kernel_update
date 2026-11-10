# Debian 12 SystemVM 커널 오프라인 적용 방법

작성일: 2026-11-06

이 문서는 tar.gz 반입 방식의 적용 절차입니다. **ISO를 마운트하여 실행하는 방법과 두 형식의 생성 방법은 [BUILD.md](BUILD.md)**를 따릅니다. 두 형식에 같은 커널·의존성 및 설치기가 들어 있습니다.

이번에 생성한 tar.gz는 다음과 같습니다. 다시 빌드하면 실제 생성된 파일명을 사용합니다.

```text
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz.sha256
```

커널과 필요한 의존성, 설치기, 부팅 검사기가 모두 포함되어 있습니다. 아래 순서대로 적용합니다.

이 묶음의 부팅 검사 리비전은 `20261106-grub2-primary-3`입니다. 압축 해제 후 `head -n 1 BOOT-CONFIG-REVISION.txt`로 확인합니다.

**반입 → 체크섬 확인 → 압축 해제 → check → install → check-boot → 직접 재부팅 → verify → 서비스 확인**

모든 명령은 root 계정에서 실행합니다. 먼저 대표 복제본에서 설치·재부팅·역할별 기능을 검증한 뒤 운영 VM에 적용합니다.

## 1. 적용 대상과 버전

| 항목 | 값 |
| --- | --- |
| 운영체제 | Debian 12 / bookworm |
| 아키텍처 | amd64 |
| 대상 취약점 | CVE-2026-43499 |
| 커널 패키지 | `linux-image-6.1.0-54-amd64` |
| Debian 패키지 버전 | `6.1.190-1` |
| 적용 후 예상 실행 커널 | `6.1.0-54-amd64` |
| 포함된 설치 파일 | `.deb` 47개 |
| 아카이브 크기 | 약 84 MiB |

이 버전은 현재 제공하는 통합 묶음의 버전입니다. 준비 스크립트로 새로 생성하면 파일명과 제공 커널이 달라질 수 있습니다.

## 2. 적용 전 준비

대상 VM에서 운영체제, 아키텍처 및 패키지 상태를 확인합니다.

```bash
cat /etc/os-release
dpkg --print-architecture
uname -r
dpkg --audit
apt-mark showhold
df -h / /boot /lib/modules /var/tmp
```

Debian 12/amd64인지 확인하고, dpkg 오류나 업데이트를 막는 hold가 있으면 먼저 원인을 확인합니다. 아카이브·압축 해제 파일·패키지 캐시·신규 커널 모듈·initramfs가 들어갈 공간도 확보합니다.

운영 적용 전에는 복구 가능한 VM/디스크 백업과 하이퍼바이저 콘솔을 준비합니다. 복제본은 운영 VM과 IP가 충돌하지 않도록 분리하고 디스크·부팅 방식을 유지합니다.

## 3. 파일 반입과 체크섬 확인

통합 아카이브와 같은 이름의 `.sha256` 파일을 함께 대상 VM의 `/home/cloud`에 반입합니다.

```bash
cd /home/cloud
sha256sum -c debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz.sha256
```

다음과 같이 `OK`가 나오면 진행합니다.

```text
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz: OK
```

정확한 SHA256 값은 동봉된 `.sha256` 파일에서 확인합니다. 무결성 검사가 실패하면 파일 전달 상태를 확인합니다.

## 4. 압축 해제

```bash
cd /home/cloud
tar -xzf debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz
cd debian12-kernel-amd64-20261106T074740Z-NJPHLu8I
```

이후 명령은 이 추출 디렉터리에서 실행합니다. 다른 경로에 반입했다면 실제 경로를 사용하며, 공백과 특수문자가 없는 경로에 추출합니다.

| 파일·디렉터리 | 내용 |
| --- | --- |
| `install-kernel.sh` | 설치 전 점검·설치·부팅 항목 및 실행 커널 검증 |
| `kernel-boot-check.sh` | GRUB 부팅 항목 검사기 |
| `repo/` | 커널과 의존성 `.deb` 47개 및 로컬 APT 인덱스 |
| `packages.tsv` | 포함된 전체 패키지 이름·버전 목록 |
| `SHA256SUMS` | 묶음 내부 파일의 체크섬 |
| `logs/` | 이 VM에서 실행한 설치 계획·설치 로그 |
| `source/` | 묶음 재생성을 위한 준비 스크립트와 보조 파일 |

`packages.tsv`는 반입한 전체 패키지 목록입니다. 실제 설치·갱신할 패키지는 각 VM의 기존 상태에 따라 선택됩니다.

## 5. 설치 전 점검

```bash
bash install-kernel.sh check
```

반입한 로컬 저장소만 사용하여 무결성, 대상 환경, 기존 패키지 상태, 의존성, hold, 부팅 구성 및 신규 커널 설치 공간을 점검합니다. 이 단계에서는 패키지를 설치하지 않습니다.

정상 종료 시 다음 문구를 확인합니다.

```text
Local dependency and package integrity checks passed.
Preflight passed. Plan: .../logs/...-check-plan.txt
No packages installed. ...
```

설치 계획에서 커널·메타패키지 및 필요한 의존성의 추가·갱신 내역을 확인합니다. check가 실패하면 원인을 해결한 뒤 다시 실행합니다.

## 6. 커널 설치

점검을 통과한 뒤 실행합니다.

```bash
bash install-kernel.sh install
```

설치기는 사전 점검을 반복하고 목표 버전과 필요한 의존성을 설치한 뒤 initramfs와 부팅 설정을 갱신합니다. 이 환경에서는 기존 `/boot/grub/grub.cfg`를 검증하고 `grub-mkconfig`로 GRUB2 설정 후보를 생성합니다. 후보의 커널·initrd·문법·기본 부팅 항목 검증이 통과한 뒤 반영합니다.

설정 백업은 출력되는 `/boot/grub/kernel-offline-backup.*` 경로에 보관됩니다. 생성이나 검증이 실패하면 기존 GRUB2 설정을 보존하고 중단합니다. 디스크의 부트로더나 MBR/EFI는 재설치하지 않습니다.

정상 완료 메시지:

```text
Installed 6.1.0-54-amd64. No reboot performed.
```

자동 재부팅, 기존 커널 패키지 제거 및 autoremove는 수행하지 않습니다. 같은 ABI의 패키지를 갱신하는 경우 이전 빌드 파일은 교체될 수 있습니다. 설치 도중 오류나 `Do not reboot` 메시지가 있으면 원인을 해결하기 전에는 재부팅하지 않습니다.

## 7. 재부팅 전 부팅 항목 점검

```bash
bash install-kernel.sh check-boot
```

설치된 목표 커널 버전, dpkg 상태, 커널·initramfs·모듈 파일 및 부팅 메뉴의 일치 여부를 읽어서 검사합니다. 이 명령은 패키지 설치나 부팅 파일 갱신을 수행하지 않습니다.

정상 종료 시:

```text
Validated entry: ...
Boot entry check passed. ...
```

`/boot/grub/grub.cfg`의 같은 메뉴 항목에 신규 커널과 일치하는 initrd가 있어야 하고, 기본 첫 번째 항목도 새 커널을 선택해야 합니다. 저장된 항목이나 `next_entry` 재정의처럼 수동 확인이 필요한 설정은 중단하여 검토하도록 안내합니다.

기본값이나 저장된 부팅 항목이 새 커널을 선택하는지 콘솔에서 확인합니다. 메뉴 검사만으로 디스크·펌웨어·하이퍼바이저가 실제 선택하는 부트로더까지 확인되지는 않습니다. 이전 커널 선택 또는 백업 복원 방법도 준비합니다.

## 8. 재부팅

점검 시간에 직접 실행합니다.

```bash
reboot
```

## 9. 실행 커널과 서비스 확인

재접속 후 실행합니다.

```bash
cd /home/cloud/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I
bash install-kernel.sh verify
uname -r
systemctl --failed
```

정상 확인값:

```text
Verified: running 6.1.0-54-amd64, Debian build 6.1.190-1, CVE-2026-43499 fixed since 6.1.176-1.
```

`verify`는 실행 커널의 ABI, 설치된 패키지 버전 및 `/proc/version`의 Debian 빌드를 함께 비교합니다. `uname -r`은 `6.1.0-54-amd64`여야 합니다. 실패한 서비스가 있으면 업데이트 전 상태와 비교합니다.

| 역할 | 기능 확인 |
| --- | --- |
| SSVM | 템플릿·ISO 업로드/다운로드 |
| CPVM | 가상머신 콘솔 접속 |
| Virtual Router | 실제 사용하는 DHCP·DNS·NAT·방화벽·VPN 등 |

구성이 다른 템플릿별로 대표 복제본을 검증하고, 운영 VM마다 같은 점검·설치·재부팅·검증 절차를 수행합니다.

## 10. 목표 커널이 이미 설치된 VM

이미 목표 커널 설치가 완료된 대상은 다음 명령으로 부팅 항목을 확인합니다.

```bash
bash install-kernel.sh check-boot
```

실행 커널이 아직 구버전이면 부팅 선택과 복구 방법을 확인한 뒤 점검 시간에 재부팅하고 `verify`를 실행합니다. 이미 목표 빌드로 실행 중이며 `verify`가 통과하면 이번 커널 업데이트를 위한 설치와 재부팅은 생략할 수 있습니다.

## 11. 오류가 발생하면

| 오류·상태 | 조치 |
| --- | --- |
| 체크섬 또는 내부 무결성 검사 실패 | 정상 아카이브와 체크섬을 다시 전달하고 새 디렉터리에 추출합니다. |
| 의존성 계산 실패 | 대상의 패키지 상태를 수집하여 필요한 의존성을 포함한 묶음을 다시 준비합니다. |
| 변경 예정 패키지에 hold가 있음 | hold 사유와 변경 계획을 확인합니다. |
| DKMS 모듈이 있음 | 일치하는 헤더·빌드 의존성을 포함한 별도 구성을 준비·검증합니다. |
| GRUB 업데이터·출력 파일 불일치 또는 부팅 항목 누락 | 실제 부팅 방식과 생성 파일을 확인한 뒤 점검합니다. |
| 디스크 공간 부족 | 필요한 파일시스템에 공간을 확보하고 다시 점검합니다. |
| 더 최신 커널 패키지가 설치됨 | 현재 실행 빌드를 확인하고 필요하면 더 최신 묶음을 준비합니다. |
| 재부팅 후 구버전으로 실행됨 | 커널 재설치나 반복 재부팅을 하기 전에 부팅 시각, 실제 부트로더가 읽는 설정, 기본·저장된 항목 및 하이퍼바이저의 커널 선택을 확인합니다. 사용하지 않는 과거 부팅 도구가 남아 있을 수 있으므로 현재 설정을 기준으로 확인합니다. |

실패 시 `logs/`와 `Diagnostic APT files retained: ...` 경로의 진단 자료를 보관합니다.

`install` 완료와 부팅 메뉴 등록만으로 실제 커널 전환을 완료했다고 판단하지 않습니다. 재부팅 후 `verify`와 `/proc/version`까지 일치해야 합니다. `systemctl --failed`가 0개라는 결과도 새 커널로 부팅됐다는 증거는 아닙니다.

### 설치된 새 커널이 GRUB2 메뉴에 없을 때

이미 새 커널 설치와 initramfs 생성이 완료됐지만, 실제 부팅에 사용되는 `/boot/grub/grub.cfg`에 구버전만 있는 경우에는 해당 설정을 백업하고 재생성합니다. 아래 명령은 현재 대상에서 확인된 경로를 기준으로 합니다.

```bash
cp -pn /boot/grub/grub.cfg /boot/grub/grub.cfg.before-kernel-54
grub-mkconfig -o /boot/grub/grub.cfg
grub-script-check /boot/grub/grub.cfg
grep -n -E '^[[:space:]]*(menuentry|linux|initrd)[[:space:]]' /boot/grub/grub.cfg
grub-editenv /boot/grub/grubenv list
```

새 커널 `6.1.0-54-amd64`와 일치하는 initrd, 기본 부팅 항목을 확인합니다. 문법 검사 실패나 다른 커널을 선택하는 `next_entry`가 있으면 재부팅 전에 해결합니다. 점검 시간에 재부팅한 뒤 9절의 verify를 수행합니다. 현재 설치기는 기존 grub.cfg를 우선 사용하여 같은 갱신 누락을 방지합니다.

## 12. 대상별 추가 의존성 수집

기본 묶음은 빈 dpkg 상태에서 선택된 필수 의존성을 포함합니다. 기존 설치 패키지의 버전 제약이나 역의존성 때문에 다른 구성의 VM에서 추가 파일이 필요할 수 있습니다.

대표 대상 VM의 추출 디렉터리에서 상태를 수집합니다. 출력 경로는 새 디렉터리 이름을 사용합니다.

```bash
bash collect-systemvm-state.sh /root/systemvm-state-vm-a
```

수집한 디렉터리를 인터넷 가능한 다운로드 VM으로 옮기고, 준비 스크립트와 보조 파일이 있는 디렉터리에서 대상별 status를 반영하여 새 묶음을 생성합니다.

```bash
bash prepare-debian12-kernel-offline.sh ./output \
  --target-status ./vm-a/status \
  --target-status ./vm-b/status
```

새로 생성된 파일명과 버전에 맞춰 같은 반입·설치 절차를 진행합니다.

## 13. 템플릿 반영과 작업 기록

현재 VM의 변경은 원본 SystemVM 템플릿에 자동으로 반영되지 않습니다. 재생성되는 VM에도 유지하려면 사용 중인 제품 버전과 호환되는 템플릿을 별도로 갱신·검증합니다.

설치기 수정 이유와 검증 이력은 `plan.md`에 기록합니다. 이 적용 문서는 최종 통합 묶음의 실행 절차를 안내합니다.
