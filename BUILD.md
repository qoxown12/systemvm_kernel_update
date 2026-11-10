# Debian 12 커널 tar.gz·ISO 빌드 방법

작성일: 2026-11-06

이 문서는 인터넷 가능한 Debian 12/amd64 준비 VM에서 커널과 의존성을 수집하고, 에어갭 대상에 전달할 tar.gz 및 ISO를 만드는 방법입니다. 두 형식은 같은 검증된 tar payload를 사용하므로 커널·패키지 구성이 같습니다.

## 1. 빌드 환경과 파일

커널 다운로드 준비 스크립트는 root에서 실행합니다. ISO 생성 자체는 필요한 파일과 출력 경로에 접근 가능한 일반 계정에서도 실행할 수 있습니다.

인터넷 가능한 준비 VM에서 필요한 도구를 설치합니다.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates debian-archive-keyring python3 genisoimage
```

`genisoimage`에는 생성 이미지의 파일을 다시 읽어 검사하는 `isoinfo`도 포함됩니다. 대상 VM에는 ISO 빌드 도구를 설치할 필요가 없습니다.

작업 디렉터리 예시는 `/root/rpm`입니다. 아래 파일들을 같은 디렉터리에 둡니다.

```text
prepare-debian12-kernel-offline.sh  # 커널 다운로드와 tar.gz 생성
kernel-offline-tools.py            # CVE/패키지 검사 및 로컬 인덱스 생성
kernel-boot-check.sh               # 부팅 구성 점검·갱신
install-kernel-offline.sh          # tar 내부의 install-kernel.sh 원본
collect-systemvm-state.sh          # 실제 대상 패키지 상태 수집
README-KO.txt
build-kernel-iso.sh                # tar.gz를 데이터 ISO로 변환
run-kernel-from-iso.sh             # ISO 루트의 install-kernel.sh 원본
BUILD.md
INSTALL.md
```

tar.gz만 만들 때는 첫 여섯 파일이 필요합니다. ISO를 만들 때는 ISO 빌드 스크립트와 실행기 원본도 필요합니다. 가이드 파일은 있을 때 결과물에 함께 포함됩니다. `history`, `tests` 폴더는 필수가 아닙니다.

## 2. 커널·의존성 다운로드와 tar.gz 생성

```bash
cd /root/rpm
sudo bash prepare-debian12-kernel-offline.sh ./output
```

`output`이 없으면 자동 생성합니다. 스크립트는 다음을 수행합니다.

1. 공식 Debian 트래커에서 CVE-2026-43499의 bookworm 수정 하한을 확인합니다.
2. 서명된 bookworm/main, bookworm-updates/main, bookworm-security/main 인덱스를 조회합니다.
3. 빈 dpkg 상태로 커널과 선택된 필수 의존성을 수집합니다.
4. 로컬 APT 저장소, 패키지 목록, 설치기, 체크섬과 tar.gz를 생성합니다.
5. 로컬 저장소만으로 의존성을 다시 계산하여 확인합니다.

다운로드 VM에는 커널을 설치하지 않습니다. 실행 시점의 저장소를 사용하므로 커널 버전, 패키지 개수, 생성 파일명은 달라질 수 있습니다.

출력 예:

```text
output/
  debian12-kernel-amd64-생성시각-식별자.tar.gz
  debian12-kernel-amd64-생성시각-식별자.tar.gz.sha256
  build.식별자/                         # 다운로드·검증 작업 파일
```

명령 마지막에 출력되는 `Archive:`의 실제 tar.gz 경로를 기록합니다. 아래 ISO 생성 명령의 `kernel_archive`에 그 경로를 넣습니다.

## 3. 여러 대상 VM 상태 반영

대상 구성이 다르면 각 대표 VM에서 root로 상태를 수집합니다.

```bash
bash collect-systemvm-state.sh /root/systemvm-state-vm-a
```

그 디렉터리를 다운로드 VM으로 옮긴 후 status 경로를 지정합니다.

```bash
sudo bash prepare-debian12-kernel-offline.sh ./output \
  --target-status ./vm-a/status \
  --target-status ./vm-b/status
```

생성된 해당 tar.gz를 ISO로 변환하면 추가 의존성이 반영된 동일한 세트가 ISO에 들어갑니다.

## 4. tar.gz를 ISO로 변환

`kernel_archive`를 2절에서 실제 생성된 파일 경로로 바꿉니다.

```bash
cd /root/rpm
kernel_archive='/root/rpm/output/실제로-생성된-파일명.tar.gz'
bash build-kernel-iso.sh "$kernel_archive"
```

기본 출력은 입력 tar.gz와 같은 디렉터리의 같은 이름 `.iso`와 `.iso.sha256`입니다. 원하는 출력 파일명을 직접 지정할 수도 있습니다.

```bash
bash build-kernel-iso.sh "$kernel_archive" /root/rpm/output/debian12-kernel-offline.iso
```

기존 ISO나 같은 이름의 체크섬이 있으면 덮어쓰지 않고 중단합니다. 재빌드 시에는 새 출력 파일명을 지정합니다.

ISO 빌드 스크립트는 tar 내부 체크섬과 구조를 검증하고, 필요한 파일만 별도 작업 경로에 준비합니다. 작업 프로젝트 전체를 ISO에 넣지 않습니다. 마지막에는 `isoinfo`로 ISO의 모든 파일을 다시 읽고 원본 SHA256과 비교한 뒤 완료 처리합니다.

## 5. ISO 내부 구조와 실행 방식

```text
ISO 루트/
  install-kernel.sh         # 마운트 후 실행하는 진입 스크립트
  README-ISO-KO.txt
  BUILD.md
  INSTALL.md
  plan.md                  # 파일이 있을 때 포함하는 작업 이력
  SHA256SUMS
  bundle-name.txt
  payload-file.txt
  payload-sha256.txt
  payload-SHA256SUMS
  kernel-package.txt
  kernel-version.txt
  payload/
    debian12-kernel-amd64-생성시각-식별자.tar.gz
  source/
    build-kernel-iso.sh
    run-kernel-from-iso.sh
```

ISO는 VM의 CD/DVD로 연결하는 데이터 매체입니다. 운영체제 설치용 부팅 ISO를 만드는 절차는 아닙니다.

마운트한 스크립트는 다음 순서로 동작합니다.

1. ISO 안의 파일과 tar payload 무결성을 확인합니다.
2. VM의 `/var/lib/systemvm-kernel-offline`에 검증한 묶음을 자동으로 압축 해제합니다.
3. 이후 실행은 같은 payload의 로컬 복사본을 검증하여 재사용합니다.
4. 쓰기 가능한 로컬 경로에서 기존 설치기의 check/install/check-boot/verify를 실행합니다.

사용자가 수동으로 tar를 풀 필요는 없습니다. ISO에 로그나 캐시를 쓰지 않습니다. 기존에 검증한 커널 설치기와 GRUB2 처리 로직을 그대로 사용합니다.

추출된 payload는 약 90 MB 수준의 별도 공간을 사용하며, 여기에 신규 커널 모듈·initramfs·APT 캐시 공간도 필요합니다. 실제 설치 계획과 `df -h`를 확인합니다.

## 6. VM에 ISO 연결 후 실행

ISO와 체크섬을 신뢰할 수 있는 경로로 반입하고, 제품 관리 화면 또는 하이퍼바이저에서 대상 VM의 CD/DVD에 ISO를 연결합니다. ISO 파일을 보유한 환경에서 동봉 `.iso.sha256`로 확인합니다.

```bash
cd /ISO와-체크섬이-있는-경로
sha256sum -c 실제-생성한-파일명.iso.sha256
```

아래 명령은 대상 VM의 root 기준입니다. 일반 계정은 sudo를 사용합니다.

```bash
lsblk -o NAME,TYPE,SIZE,FSTYPE,LABEL,MOUNTPOINTS
mkdir -p /mnt/kernel-offline
mount -t iso9660 -o ro /dev/sr0 /mnt/kernel-offline
bash /mnt/kernel-offline/install-kernel.sh check
```

`/dev/sr0`는 예시입니다. lsblk에서 실제 CD 장치를 확인합니다. 볼륨 이름은 `DEB12_KERNEL`입니다.

check가 통과하면 실행합니다.

```bash
bash /mnt/kernel-offline/install-kernel.sh install
bash /mnt/kernel-offline/install-kernel.sh check-boot
```

설치기는 자동 재부팅하지 않습니다. 기본 부팅 항목과 복구 방법을 확인한 뒤 점검 시간에 직접 재부팅합니다.

```bash
reboot
```

## 7. 재부팅 후 검증

ISO를 다시 마운트하지 않고 로컬 복사본에서 검증할 수 있습니다.

```bash
bash /var/lib/systemvm-kernel-offline/current/install-kernel.sh verify
uname -r
systemctl --failed
```

ISO가 마운트되어 있으면 다음 명령도 가능합니다.

```bash
bash /mnt/kernel-offline/install-kernel.sh verify
```

로그는 `/var/lib/systemvm-kernel-offline/current/logs/`에 저장됩니다. current는 마지막으로 준비한 검증 payload 디렉터리를 가리키는 링크입니다.

실행 커널·Debian 빌드가 해당 묶음의 목표 버전과 일치하는지 확인하고, SSVM/CPVM/VR 등 실제 역할의 서비스 기능도 점검합니다. 운영 VM 적용 전에는 대표 복제본의 설치·재부팅 검증 및 백업·콘솔을 준비합니다.

## 8. 정리와 보관

- 전송·배포용으로 ISO+체크섬 또는 tar.gz+체크섬 한 세트를 보관합니다.
- 빌드가 완료되면 output의 build.* 작업 파일은 결과물을 보존한 상태에서 정리할 수 있습니다.
- ISO 빌드용 .iso-build.*는 성공 시 자동 정리합니다. 실패 시 진단을 위해 경로를 표시하고 남깁니다.
- 대상의 로컬 캐시는 설치·재부팅·verify·서비스 확인이 끝날 때까지 보존합니다.
- 캐시 경로를 바꿀 때는 `KERNEL_OFFLINE_CACHE_DIR` 환경 변수를 root 실행에 전달하고, 이후 검증 경로도 그 위치를 사용합니다.
- 마운트 경로와 캐시 경로는 공백·특수문자가 없는 절대 경로를 사용합니다.

## 공식 도구 참고

- [genisoimage](https://manpages.debian.org/bookworm/genisoimage/genisoimage.1.en.html)
- [isoinfo](https://manpages.debian.org/bookworm/genisoimage/isoinfo.1.en.html)
- [mount](https://manpages.debian.org/bookworm/mount/mount.8.en.html)
