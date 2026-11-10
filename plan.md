# Debian 12 제품 가상머신 커널 오프라인 업데이트

## 최종 적용 기준

현재 대상 검증 상태: 첫 KO2 대상 `...b374d`는 재부팅 후 verify 통과, 실행 커널 `6.1.0-54-amd64`, Debian 빌드 `6.1.190-1`, 실패 서비스 0개가 확인됐다. 두 번째 KO2 대상 `...b7932`도 check에 이어 실제 커널 설치 및 GRUB2 설정 생성·문법·기본 항목 검증이 정상 완료됐다. 두 번째 대상의 재부팅 후 verify 및 역할별 기능 검증 결과는 아직 받지 않았다.

- 이번 생성 파일: `output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz`, 같은 이름의 `.iso`, 각 `.sha256`.
- 기존 `...-grubfix1.tar.gz` 및 체크섬은 정리됐다. 새 결과물에는 검증한 GRUB2 처리 리비전 `20261106-grub2-primary-3`을 그대로 사용한다.
- 정확한 결과물 SHA256은 함께 제공하는 `.sha256`를 기준으로 확인한다. 아래 이전 파일명과 해시는 각 작업 시점의 이력이다.
- tar.gz 적용은 **`INSTALL.md`**, tar.gz·ISO 생성 및 ISO 마운트·실행은 **`BUILD.md`**를 따른다.
- cloud SSH를 통한 자동 전송·설치·재부팅·검증은 별도 `deploy-systemvm-kernel.sh`와 `REMOTE-INSTALL.md`를 사용한다.
- 원격 실행 입력 형식은 `-k SSH_KEY -f PATCH.tar.gz -i TARGET_IP -p SSH_PORT`이다. 적용·점검 모드에서 패치 경로는 `-f`로 명시한다. 재검증 전용 `--verify-only RUN_ID`에는 `-f`가 필요 없다.
- 원격 컨트롤러 실행 환경은 Rocky Linux 9 / Python 3.9 이상이며, 커널 적용 대상은 Debian 12 amd64 SystemVM 또는 SystemVM 템플릿 기반 관리형 Kubernetes 노드다. 기본 전송은 scp/SFTP, 명시적 `--scp-legacy`는 scp -O를 사용한다. 현재 원격 적용기 리비전은 `20261106-rocky9-cks-1`이다.
- 적용 순서: 반입 → 체크섬 확인 → 압축 해제 또는 ISO 마운트 → check → install → check-boot → 직접 재부팅 → verify → 서비스 확인.
- 설치기 및 GRUB 검사 수정은 통합본에 포함되어 있다.
- 아래 초기 아카이브·작은 패치·오류 조치 내용은 제작·검증 과정의 이력이다. 신규 적용은 현재 생성한 결과물과 위 문서를 따른다.

현재 부팅 정책: `/boot/grub/grub.cfg`를 검증하고 직접 갱신한다. GRUB2 적용에서 `menu.lst`를 요구하거나 수정하지 않는다. 아래의 과거 'Legacy 우선' 또는 '두 형식을 모두 검사' 설명은 당시 리비전의 이력이며 현재 적용 조건이 아니다.

## 추가 이력: 제품 기준 Markdown 문서 정리 (2026-11-06)

- 사용자 요청에 따라 Markdown의 업스트림 제품 명칭, 해당 플랫폼 전용 설명 및 관련 링크를 제거하고 제품 가상머신·SystemVM·관리형 Kubernetes 노드 표현으로 정리했다.
- 실제 적용에 필요한 `cloud` 계정, `type=cksnode`, 설치 파일명, 옵션, 커널 버전과 작업 이력은 유지했다. 릴리스 식별 파일은 문서에서 제품 식별 정보로 설명하며 프로그램 내부의 실제 경로나 검사를 바꾸지 않았다.
- 프로젝트의 Markdown 원본 5개와 빌드 작업 폴더의 문서 사본 4개를 확인했다. 사본은 해당 원본으로 동기화하고 기존 내부 체크섬 중 변경 문서 항목만 갱신했다. 패키지·스크립트의 체크섬을 유지하면서 보호 파일 85개의 작업 사본 무결성을 확인했다.
- Markdown 파일 9개에서 제거 대상 명칭·링크의 잔여 항목이 없음을 확인했다. 현재 사용 가이드의 Bash 명령 문법도 확인했다. 아래 과거 검증 기록의 꺾쇠 자리표시자 예시는 당시 명령 형식 설명이다.
- 이미 생성한 tar.gz·ISO와 외부 체크섬은 보존한다. 해당 파일 안의 문서는 이전 빌드 시점 사본이며, tar.gz를 새로 생성하고 그 파일로 ISO를 생성할 때 정리한 문서가 포함된다.

## 추가 이력: 실제 Rocky 9 실행 로그 및 cksnode 식별 지원 (2026-11-06)

- 사용자가 ccvm에서 Python 3.9.25로 현재 tar.gz를 검증하고 대상 SSH·sudo·Debian/VM/템플릿 확인까지 진행한 로그를 전달했다. 실행 ID는 `20261106T092748Z-tjt9PigW`이며 `Unknown or ambiguous SystemVM type`에서 중단됐다. 이 실패 실행에서는 파일 전송, 커널 설치 및 재부팅이 수행되지 않았다.
- type 필드만 읽는 원격 조회 결과는 `type=cksnode`였다. CKS는 SystemVM 템플릿을 기반으로 노드를 배포할 수 있으며, 기존 검사기가 SSVM/CPVM/VR 계열만 가정하여 관리형 Kubernetes 역할을 누락한 것이 원인이었다. Rocky/Python 호환 오류는 아니었다.
- `cksnode`를 별도 제품 가상머신 분류로 지원했다. 기존 Debian 12/amd64, VM, 제품 템플릿 파일 및 역할 검사를 유지하고, 관리형 Kubernetes 노드에는 추가로 로드된 kubelet 또는 etcd 서비스를 요구한다. 알 수 없는 역할, 누락/복수 역할, 템플릿 증거가 없는 대상은 계속 거절한다.
- CKS의 재부팅 후 필수 서비스에는 kubelet 또는 전용 etcd를 포함한다. containerd·Docker 등 재부팅 전 실행 서비스도 기존 스냅샷으로 복귀를 검사한다. CKS에는 미사용 SystemVM enabled_svcs 역할 목록이나 SSVM/CPVM cloud.service를 요구하지 않는다.
- 컨트롤러와 원격 로그에 VM 분류를 표시하고, 누락 역할·복수 역할·지원하지 않는 역할의 오류를 구분한다. 수정본 확인을 위해 도움말과 실행 로그에 리비전 `20261106-rocky9-cks-1`을 출력한다. `-k/-f/-i/-p` 실행 형식은 유지했다.
- 관리형 Kubernetes 식별·서비스 관련 모의 검사 14개를 통과했다. 실제 Bash 작업기의 Kubernetes 구성 증거 확인, 원래 6개 SystemVM 역할, 누락/알 수 없는/충돌 역할 차단, 관리형 Kubernetes 서비스 없는 대상 거절, 전용 etcd, 템플릿 증거 필수, 관리형 Kubernetes 서비스 스냅샷과 미사용 템플릿 서비스 제외, 정상 재부팅 후 검증, kubelet/런타임 미복귀 차단, 컨트롤러의 관리형 Kubernetes 점검 진행·일반 VM SCP 전 차단 및 셸/문서 문법을 확인했다.
- 위 신규 검사는 임시 fixture의 VM 파일·서비스·SSH/SCP·커널 검증기를 사용했다. 이 작업 공간에서 실제 대상에 접속하거나 설치·재부팅하지 않았다. 사용자 실제 로그로 확인한 범위는 Rocky 9 컨트롤러의 파일 검증 및 SSH/sudo/역할 조회까지다. 새 리비전의 대상 설치 결과는 아직 받지 않았다.
- Kubernetes Node Ready·Pod 상태는 관리자 kubectl 환경에서 별도 확인한다. cordon/drain/uncordon은 스크립트가 자동 수행하지 않으며 노드별 점검 순서는 클러스터 운영 절차에서 관리한다. 사용 가이드에 해당 범위와 수정본 식별 방법을 반영했다. 기존 커널 tar.gz와 ISO는 변경하지 않았다.

## 추가 이력: Rocky Linux 9 원격 실행 환경 대응 (2026-11-06)

- 사용자가 원격 실행 VM의 OS를 Rocky Linux 9로 지정했다. 대상 VM은 기존 Debian 12/amd64 SystemVM을 유지하며 컨트롤러에 Debian 패키지 도구를 요구하지 않는다.
- Rocky 9 기본 Python 3.9에서 사용할 수 없는 Python 3.11 전용 `hashlib.file_digest` 호출을 제거했다. tar.gz와 각 tar 멤버를 1 MiB 단위로 읽는 표준 SHA256 함수로 변경하여 메모리 사용을 제한하고 내부·외부 무결성 검사를 유지했다. 체크섬 파일은 UTF-8로 읽는다.
- 실행 전 Bash 4.4 이상, Python 3.9 이상 및 명령 의존성을 검사한다. 누락 시 Rocky용 `dnf install -y bash python3 openssh-clients coreutils gawk` 준비 방법을 안내한다. Python 3.11 또는 pip 추가 설치는 필요 없다.
- Rocky 9의 scp 기본 전송인 SFTP를 사용하도록 변경했다. SystemVM에서 SFTP를 사용할 수 없는 경우 `--scp-legacy`를 명시하면 기존 scp -O 방식을 사용한다. 프로토콜 자동 재시도나 호스트의 SSH/암호화 정책 변경은 수행하지 않는다. 원격 작업기 자체에는 scp가 필요하지 않아 공통 명령 검사에서 제외했다. legacy 전송은 대상 scp 명령을 필요로 한다.
- `REMOTE-INSTALL.md`를 Rocky 9 컨트롤러와 Debian 12 대상의 구분, dnf 패키지 준비, Python 3.9 및 전송 옵션을 기준으로 갱신했다. 입력 형식 `-k/-f/-i/-p`와 cloud 계정, SystemVM·커널·서비스 검사 흐름은 유지했다.
- 검사 10개를 통과했다: Python 3.9 문법 및 file_digest 제거 조건의 전체 모의 흐름, UTF-8/공백 경로와 여러 청크의 SHA256, 기본 SFTP, 명시적 legacy 전송, SFTP 실패 시 설치 시작 차단, 지원하지 않는 Python의 접속 전 차단, verify-only, 내부·외부 해시 변조 차단, 실제 deb 47개 아카이브 검증 및 문서 명령 문법 검사.
- 현재 작업 환경에는 Python 3.9 실행 파일과 Rocky 9 컨테이너/VM이 없어 Python 3.11에서 3.9 문법 및 API 조건을 모의했다. SSH/SCP와 재부팅은 fixture였으며 실제 Rocky 9 실행이나 대상 설치·재부팅 검증을 수행한 결과는 아니다. 기존 tar.gz와 ISO는 변경하지 않았다.

근거: [Rocky Linux 9 공식 릴리스 문서](https://docs.rockylinux.org/releases/release_notes/9_0/), [Python file_digest 추가 이력](https://github.com/python/cpython/issues/89313), [Red Hat OpenSSH 전송 방식 문서](https://www.redhat.com/de/blog/openssh-scp-deprecation-rhel-9-what-you-need-know).

## 추가 이력: 원격 실행 옵션 형식 변경 (2026-11-06)

- 사용자 요청에 맞춰 위치 인자 방식을 `bash deploy-systemvm-kernel.sh -k KEY -f PATCH.tar.gz -i IP -p PORT` 형식으로 변경했다. `-k/--key`, `-f/--archive`, `-i/--ip`, `-p/--port`를 지원하며 옵션 순서는 자유다.
- 적용·점검 모드에서는 네 입력값을 필수로 검사한다. 패치 파일 자동 탐색은 제거하고 `-f`로 지정한 파일과 그 옆의 `.sha256`를 검증한다. `--verify-only`의 기존 원격 실행 검증 기능은 패치 입력 없이 유지한다.
- 옵션 누락·값 누락·중복 입력·알 수 없는 위치 인자와 잘못된 IP/포트는 SSH 접속 전에 거절한다. 접속 계정 cloud, sudo, SystemVM 검사, 설치·재부팅·서비스 확인 로직은 유지했다.
- `REMOTE-INSTALL.md`의 모든 실행 예시와 옵션 표를 새 형식으로 수정했다. 현재 포트 예시는 `-p 2222`이며 실제 대상 포트를 입력해야 한다.
- 임시 fixture 기반 CLI/통합 검사 21개를 통과했다. 키·패치 경로의 공백 처리, SSH/SCP의 키·IP·포트·패치 전달, 전체 흐름, 옵션 순서, 긴 옵션 별칭, check-only, verify-only, IPv6, 누락·중복·IP/포트 오류·모드 충돌·구형 위치 인자 거절·도움말을 검증했다. 문서의 Bash 명령 문법도 확인했다. 실제 원격 접속·설치·재부팅은 수행하지 않았다.

## 추가 이력: cloud 계정 SSH 원격 자동 적용 최초 구현 (2026-11-06)

- 사용자 요청에 따라 `deploy-systemvm-kernel.sh`와 `REMOTE-INSTALL.md`를 추가했다. 최초 구현은 SSH 키 경로, 대상 IP, 포트 세 위치 인자를 받았으며 tar.gz를 output 또는 스크립트 옆에서 자동 탐색했다. 이후 입력 형식은 위 옵션 변경 이력대로 수정했다.
- 전송 전에 Debian 12/amd64, 실제 VM, systemd, 제품 릴리스·초기화·역할 캐시 파일과 알려진 SystemVM 역할을 모두 확인한다. 일반 VM 또는 증거가 없는 대상은 SCP 전에 거절한다. 게스트 내부 증거에 따른 판정이며 관리 API UUID 대조는 하지 않는다. 전체 cmdline이나 개인키 내용은 출력·전송하지 않는다.
- 로컬 아카이브 외부 해시 및 내부 모든 파일 해시, 단일 루트·경로·파일 형식을 검증한다. root 작업 경로에 복사한 업로드의 해시도 확인한 뒤 실행한다. SSH 키는 로컬 SSH 인증에만 사용하고 전송 대상은 tar.gz와 작업기 원본이다.
- 원격 systemd 작업은 압축 해제 → check → install → check-boot 순서로 실행한다. 오류가 나면 FAILED 상태와 실패 단계를 기록하고 다음 단계 및 재부팅을 실행하지 않는다. SSH 단절은 이미 시작된 APT/dpkg를 종료하지 않는다. 대상별 잠금을 설치부터 재부팅까지 유지한다.
- 모든 사전 단계가 통과한 경우에만 재부팅 타이머를 한 번 생성한다. 컨트롤러는 SSH 복귀에 더해 boot ID 변경을 요구하고, 저장한 VM 식별값과 실제 커널 ABI·Debian 빌드를 다시 확인한다.
- 재부팅 후 dpkg audit, 실패 유닛 0개, 이전에 실행 중이던 서비스·ssh·역할별 cloud 서비스 및 로드된 enabled_svcs 서비스의 복귀를 확인한다. 제한 시간 안에 통과하지 않으면 오류를 반환한다. 제품 역할별 실제 기능은 별도 확인해야 한다.
- `--check-only`는 전송·추출·점검만 수행한다. `--verify-only RUN_ID`는 보관된 원격 실행을 검증하며 설치·전송·재부팅을 하지 않는다. 로컬 로그와 원격 `/var/lib/systemvm-kernel-rollout/<실행ID>/`를 보존한다.
- 임시 테스트에서 컨트롤러와 실제 Bash 작업기의 의미 있는 검사 26개를 통과했다. 일반 VM·위험한 입력·해시 변조·SCP 오류 차단, 원격 준비 및 업로드 정리, 단계별 오류에서 재부팅 차단, check-only, 중복 실행 잠금, 재부팅 1회 예약, 동일 boot ID/다른 VM 거절, 정상 검증, 실패 유닛·서비스 미복귀 거절, verify-only를 포함한다. SSH/SCP·서비스·재부팅 명령은 모두 fixture였으며 실제 원격 접속이나 설치·재부팅은 수행하지 않았다.
- 별도로 실제 deb 47개가 들어 있는 현재 tar.gz를 새 스크립트의 운영용 검증 코드에 넣어 외부/내부 해시와 구조가 통과함을 확인했다. 컨트롤러·내장 작업기·문서 명령의 Bash 문법도 확인했다. 임시 테스트는 tests 폴더를 만들지 않고 수행했다.
- 기존 tar.gz와 ISO의 체크섬은 그대로 통과했다. 이번 원격 적용기는 별도 실행 파일이며, 기존 결과물을 수정하거나 다시 압축하지 않았다.

## 추가 이력: tar.gz와 마운트 실행용 ISO (2026-11-06)

- 사용자 요청에 따라 `build-kernel-iso.sh`, `run-kernel-from-iso.sh`, `BUILD.md`를 추가했다. 다운로드 준비 스크립트는 ISO 관련 원본 및 현재 문서를 선택적으로 동봉한다. 기존 커널 설치·GRUB2 갱신 코드는 변경하지 않았다.
- 기존 배포 파일을 정리한 상태였으므로 공식 서명된 저장소에서 다시 다운로드했다. CVE 수정 하한 `6.1.176-1`, 목표 `linux-image-6.1.0-54-amd64=6.1.190-1`, deb 47개를 확인하고 로컬 저장소만의 의존성 계산을 통과했다. 준비 VM의 패키지 설치나 재부팅은 수행하지 않았다.
- ISO는 볼륨 `DEB12_KERNEL`인 Rock Ridge/Joliet 데이터 ISO다. 검증한 tar.gz를 payload로 포함하며, 부팅용 OS 설치 ISO를 만드는 방식은 아니다.
- 마운트 후 ISO 루트의 `install-kernel.sh`를 실행하면 SHA256 검증 → `/var/lib/systemvm-kernel-offline/<payload-hash>/`에 자동 준비 → 기존 설치기로 위임한다. 사용자는 수동 압축 해제가 필요 없다. 로그·APT 작업은 VM의 쓰기 가능한 경로를 사용하며 ISO에는 쓰지 않는다.
- 동시 실행 잠금, payload별 캐시 재사용과 변조 검사, 임시 추출 후 원자적 반영, 실행기 오류 코드 전달을 구현했다. `current` 링크로 마지막 준비 묶음을 가리켜 재부팅 후 ISO 없이 verify할 수 있다.
- ISO 생성기는 입력 tar의 모든 파일 체크섬과 단일 루트 경로를 검사하고 링크·장치·상위 경로를 거절한다. 프로젝트 전체를 복사하지 않고 지정 파일만 포함한다. 생성 후 `isoinfo`로 ISO의 모든 파일을 다시 읽어 원본 SHA256과 비교한다.
- 임시 fixture 기반 통합 검사 11개를 통과했다: ISO 생성/전체 read-back, 첫 실행과 재사용, 위임 오류 코드, 매체 불변·로컬 로그, 매체 없는 캐시 실행, 동시 실행 거절, 캐시/매체 변조 거절, 위험 경로 거절, 기존 ISO 덮어쓰기 거절. 실제 패키지는 설치하지 않았다. 테스트 파일은 임시 경로에서 정리하여 tests 폴더를 다시 만들지 않았다.
- 문서의 이전 grubfix1 고정 파일명을 이번 결과물로 갱신하고 ISO 절차를 연결했다. 이후 재생성 시 파일명과 버전은 실제 생성 결과를 기준으로 사용한다.
- ISO 전체 파일 검증과 실행기 검증은 실제 VM의 CD 연결·마운트·커널 설치·재부팅 검증을 대신하지 않는다. 이 환경에서는 해당 VM 작업을 수행하지 않았다.

묶음 안의 plan.md는 압축 직전 이력 스냅샷이다. 최종 아카이브/ISO의 자체 해시는 외부 `.sha256`에서 확인한다.

최종 생성·검증 결과:

| 결과물 | 크기 | SHA256 |
| --- | --- | --- |
| `output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz` | 87,505,375 bytes | `1a1c6b880f441ceb89f9516fdb8cd1f86a3f0702ae54c3be66625a3517e5eca3` |
| `output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.iso` | 88,008,704 bytes | `972622e7ac02bae174a314e513556a29cda169fe9774d3b7055012492fa85984` |

- tar 내부 보호 파일 85개와 deb 47개를 확인했다. 문서와 재생성 소스를 갱신하는 과정에서도 인증 다운로드한 deb는 변경하지 않았다.
- 최종 ISO의 파일 16개 전체를 read-back하여 payload 포함 SHA256을 확인했다. 외부 tar.gz/ISO 체크섬도 각각 통과했다.
- 실제 ISO에서 읽은 파일과 payload로 임시 매체 디렉터리를 구성하여 실행기의 자동 추출과 실제 설치기 verify를 검증했다. 준비 VM에서 이미 실행 중이던 `6.1.0-54-amd64`, Debian `6.1.190-1` 검증을 통과했고, 캐시 경로에서 직접 verify도 통과했다. 매체 파일은 변경되지 않았다.
- 수정한 셸 원본과 빌드·적용 문서의 Bash 명령 문법을 확인했다. 임시 검증 경로는 정리했다. 위 검증은 ISO의 실제 CD 마운트나 새로 커널을 설치·재부팅한 시험은 아니다.

## 목적과 범위

- 작업일: 2026-11-06 (한국 시간).
- 입력: 사용자가 첨부한 기존 대화 및 `prepare-debian12-kernel-offline.sh`.
- Debian 12 / bookworm / amd64 SystemVM의 CVE-2026-43499를 해결할 커널과 필요한 `.deb` 의존성을 실제 다운로드한다.
- 다운로드 VM보다 실행 커널이 낮은 여러 SystemVM에 같은 저장소를 반입하여 적용하는 것이 목적이다. 실행 커널 버전은 의존성 계산 기준이 아니며 OS 릴리스, 아키텍처, 설치된 패키지 상태가 기준이다.
- 다른 Debian 릴리스/아키텍처, 모든 과거 커널 릴리스 수집은 범위에 포함하지 않는다. 여러 구버전 VM을 하나의 수정된 최신 커널로 올리는 설치 세트를 만든다.
- 실행 중 VM의 커널 설치/재부팅은 이번 작업에서 수행하지 않는다.

## 확인된 근거

공식 트래커: https://security-tracker.debian.org/tracker/CVE-2026-43499

2026-11-06 확인값:

| 항목 | 버전 / 상태 |
| --- | --- |
| Debian 12 `linux` 최초 수정 소스 버전 | `6.1.176-1` |
| Bookworm security 제공 소스 버전 | `6.1.190-1`, fixed |
| 다운로드 VM의 설치된 커널 | `linux-image-6.1.0-54-amd64`, `6.1.190-1` |

`uname -r`의 ABI 문자열과 Debian 패키지 버전은 구분한다. 다운로드 시 트래커를 다시 읽고 실제 커널 패키지의 Debian 버전을 비교한다. 서명 커널의 `Source`는 `linux-signed-amd64`일 수 있으므로 그 소스 버전을 linux의 수정 기준과 직접 비교하지 않는다.

## 작업 이력

1. 기존 스크립트 및 첨부 대화를 검토했다. 원본은 `history/prepare-debian12-kernel-offline.original.sh`에 보존했다.
2. 기존 스크립트는 빈 dpkg 상태 기반 다운로드 및 로컬 저장소를 구현했지만 CVE 버전 하한 검사, 실제 대상 상태별 추가 의존성 수집, 완성 저장소의 의존성 재검증이 없었다.
3. 현재 작업 환경은 Debian 12 amd64이며 `dpkg-dev`, `git`, `rg`가 없다. 호스트 커널/패키지를 갱신하지 않고, `dpkg-deb`로 로컬 인덱스를 만드는 방향으로 수정한다.
4. 샌드박스에서는 DNS가 차단되어 네트워크 접근 승인을 요청했다. 승인된 curl 호출로 공식 트래커 HTML을 확보했다.
5. 작업 디스크 여유가 약 533 MiB이므로 인덱스를 압축 보관하고 중복 복사를 줄여 다운로드한다.

## 구현 및 검증 계획

- [x] 공식 Debian bookworm/main, bookworm-updates/main, bookworm-security/main만 사용하고 APT 서명 검증을 유지한다.
- [x] 트래커에서 bookworm/linux 최초 수정 버전을 읽어 실제 다운로드 커널이 그 이상인지 검사한다.
- [x] 빈 dpkg 상태로 커널/부팅 필수 의존성을 수집한다. 다운로드 VM의 기존 설치 상태를 참조하지 않는다.
- [x] 선택적으로 여러 대상 `status` 파일의 설치 계획을 계산하고 필요한 패키지를 합치는 기능을 구현했다.
- [x] 로컬 저장소, 패키지/버전 목록, 체크섬, 보안 근거, 설치 스크립트와 한국어 안내를 묶는다.
- [x] 로컬 저장소만으로 빈 상태와 합성 구버전 상태를 다시 시뮬레이션했다. 실제 오프라인 대상 status는 제공되지 않았다.
- [x] 설치기는 check/install/verify로 나누고 제거/자동 재부팅 없이 정확한 버전을 적용한다.
- [x] 실제 다운로드, 체크섬/패키지 개수/크기 확인, 현재 VM의 비설치 점검, 구버전 합성 상태의 의존성 테스트를 수행했다.
- [x] 최종 결과 및 제한사항을 이 문서에 기록했다.

## 구현 결과와 추가 이력

6. `prepare-debian12-kernel-offline.sh`를 다운로드 전용으로 수정했다. 호스트 APT 설정/후크/저장소/pin/설치 상태를 격리하고, CVE 트래커 조회 및 하한 검사를 추가했다. 파싱/서명/다운로드 오류 시 중단한다.
7. `kernel-offline-tools.py`를 추가했다. Python 표준 라이브러리와 기본 설치된 `dpkg-deb`로 트래커 파싱, 패키지 검사, APT Packages 인덱스 및 패키지 목록을 생성한다. `dpkg-dev`를 호스트에 설치하지 않아도 된다.
8. 루트 패키지는 `linux-image-amd64 initramfs-tools linux-base kmod busybox zstd`다. busybox/zstd는 initramfs 구성을 위한 명시적 보조 도구이며, 임의의 Recommends 전체를 내려받지는 않는다.
9. `collect-systemvm-state.sh`를 추가했다. 오프라인 VM에서 네트워크 접속 없이 dpkg status, OS 및 점검 보고서를 수집한다. 준비 스크립트는 반복 가능한 `--target-status FILE`로 대상별 계획을 계산하고, `--extra-package NAME`도 지원한다.
10. `install-kernel-offline.sh`는 결과물에서 `install-kernel.sh`로 제공한다. `check`는 로컬 의존성·무결성·hold·DKMS·GRUB·용량을 검사하고 설치하지 않는다. `install`은 같은 점검 후 커널 버전을 고정 설치하며 제거/자동 재부팅을 하지 않는다. GRUB 이외 부팅 방식이나 DKMS 모듈이 있으면 별도 검증이 필요하다.
11. `verify`는 `uname -r`, 설치 패키지 버전 및 `/proc/version`의 Debian 빌드 버전을 함께 비교한다. 같은 ABI 이름으로 패키지만 업데이트하고 재부팅하지 않은 상황을 성공으로 판단하지 않는다.
12. 공식 저장소에서 47개 `.deb`, 합계 약 87.3 MB를 다운로드했다. `linux-image-6.1.0-54-amd64=6.1.190-1` 및 `linux-image-amd64=6.1.190-1`을 포함한다. 현재 다운로드 VM도 이미 이 버전이므로 현재 확인된 공식 bookworm 저장소에는 이 VM보다 더 새로운 커널 후보가 없다.
13. 빌더가 만든 묶음에 최종 보완된 설치기 및 재생성용 `source/`를 동기화하고, 내부 체크섬과 전송 아카이브를 다시 생성했다. 패키지 파일은 최초 인증 다운로드한 파일 그대로다.

## 검증 결과

| 검증 | 결과 | 범위 |
| --- | --- | --- |
| 3개 Bash 스크립트 문법 | 통과 | prepare / install / collect |
| 공식 트래커 파싱 및 버전 하한 | 통과 | `6.1.176-1`; `6.1.175-1`은 하한 미달로 거절 |
| 빈 status + 로컬 저장소만으로 의존성 계산 | 통과 | 47개 패키지의 선택된 의존성 경로 |
| 구버전 커널 상태 | 통과 | **합성** Debian 12 `6.1.55-1` → `6.1.190-1`; 이전 ABI 패키지 제거 없음 |
| 누락 의존성 차단 | 통과 | 로컬 목록에서 `libkmod2` 제거 시 실패; 외부 저장소 fallback 없음 |
| 대상 상태 기반 추가 패키지 수집 | 통과 | **합성** 구버전 zstd/libzstd-dev의 정확한 버전 역의존성 테스트. 기본 47개로는 실패하고, 인증 저장소에서 추가 `libzstd-dev`를 임시 수집한 합집합은 로컬 계산 성공 |
| 변경된/파싱 불가능한 트래커 차단 | 통과 | 수정 버전을 추측하지 않고 실패 |
| 현재 다운로드 VM의 install-kernel.sh check | 통과 | 패키지 설치 없음; busybox 1개 신규 설치 예정으로 표시됨 |
| 현재 다운로드 VM의 verify | 통과 | 기존부터 실행 중인 ABI `6.1.0-54-amd64`, Debian build `6.1.190-1` 일치. 이번 작업에서 재부팅한 결과는 아님 |
| 상태 수집 스크립트 | 통과 | 다운로드 VM의 실제 status/보고서 수집; `tests/downloader-state/` |
| 실제 구버전 SystemVM 설치/재부팅/역할 검증 | 최초 준비 시 미실시 | 이후 전달된 대상의 설치 로그와 GRUB 조치는 아래 추가 이력 참조. 재부팅·역할 검증 결과는 아직 미수신 |

샌드박스에서는 APT의 setgroups/setuid가 차단되어 로컬 APT 테스트가 처음 실패했다. 승인 후 동일한 비설치 테스트를 샌드박스 밖에서 실행하여 통과했다. APT의 기본 권한 분리 기능을 끄는 방식으로 우회하지 않았다.

추가 역의존성 테스트에서 받은 `libzstd-dev`는 임시 테스트 파일로 삭제되었으며, 배포 묶음에 불필요한 개발 도구를 추가하지 않았다. 최종 배포 묶음은 기본 47개다. 이 검증은 **실제 대상의 status를 추가해야 하는 이유**를 보여주며, 빈 status만으로 모든 기존 설치 조합까지 보장된다는 뜻이 아니다.

검증 스크립트:

```bash
python3 tests/verify_bundle.py <추출된-묶음-디렉터리>
# 추가 인증 저장소 인덱스가 남아 있는 경우에만 역의존성 온라인 테스트 포함:
python3 tests/verify_bundle.py <추출된-묶음-디렉터리> <build-디렉터리>/download.conf
```

## 초기 결과물과 실행 순서 (작업 이력)

> 아래는 초기 제작 시점의 명령과 파일명을 보존한 기록입니다. 실제 대상에 적용할 때는 위 최종 통합본과 INSTALL.md를 사용합니다.

- 전송 아카이브: `output/debian12-kernel-amd64-20261106T045535Z-TS4fvBkX.tar.gz`
- 외부 체크섬: 같은 이름의 `.tar.gz.sha256`
- 추출된 원본: `output/build.TS4fvBkX/debian12-kernel-amd64-20261106T045535Z-TS4fvBkX/`
- 전체 패키지/버전 목록: 묶음 안의 `packages.tsv`
- 공식 저장소 근거: `evidence/*InRelease`, `evidence/upstream-packages.txt`, `download-sources.list`
- 다운로드/로컬 의존성 검증 로그: `validation/`
- 설치/복구/역할별 안내: `README-KO.txt`
- 재생성용 소스: 묶음 안의 `source/`

인터넷 VM에서 다시 생성:

```bash
sudo bash prepare-debian12-kernel-offline.sh ./output
# 각 실제 대상 상태를 반영하려면:
sudo bash prepare-debian12-kernel-offline.sh ./output \
  --target-status ./vm-a/status --target-status ./vm-b/status
```

에어갭 반입 후:

```bash
sha256sum -c debian12-kernel-amd64-20261106T045535Z-TS4fvBkX.tar.gz.sha256
sudo tar -xzf debian12-kernel-amd64-20261106T045535Z-TS4fvBkX.tar.gz -C /opt
cd /opt/debian12-kernel-amd64-20261106T045535Z-TS4fvBkX
sudo bash install-kernel.sh check
# 대표 복제본 설치/재부팅/서비스 검증과 복구 준비 후, 운영 VM에도 동일 절차 적용:
sudo bash install-kernel.sh install
# 점검 시간에 직접 재부팅한 뒤:
sudo bash install-kernel.sh verify
```

추출/설치 전에 아카이브와 패키지 캐시, 신규 커널 모듈 및 initramfs가 함께 들어갈 공간을 확인한다. 현재 작업 VM은 루트 파일시스템 여유가 작으므로 여기서 신규 커널 설치 검증을 시도하지 않았다.

## 아카이브 생성 후 최종 확인

- `.deb` 개수: **47개**, 패키지 합계 **87,321,628 bytes**.
- 전송 아카이브: **87,478,995 bytes (83.43 MiB)**.
- SHA256: `ca3559b2931865ea06705f8afc0a86e433b6de38354e0e8b8b0cad2b8da867e8`.
- 최종 tar.gz를 스트리밍으로 열어 내부 **80개 파일**의 체크섬 및 47개 deb 포함 여부를 검사하여 통과했다. 위험한 절대 경로/상위 경로 요소도 없음을 확인했다.
- 외부 `.tar.gz.sha256` 파일을 최종 아카이브 기준으로 갱신했다. 아카이브 내부 `plan.md`는 이 최종 해시 기록 직전의 작업 기록이다.

## 호환성과 운영 검증

### 추가 이력: 준비 프로젝트 폴더 정리 및 재생성 방법 확인 (2026-11-06)

사용자가 history/output/tests의 필수 여부와 삭제 가능 여부, output 생성 스크립트를 문의하며 정리를 원했다. 실제 의존성을 확인한 결과 history는 원본/과거 백업, tests는 선택적 검증 도구이며 준비 스크립트의 실행에 필요하지 않다. output은 생성물과 APT 작업 캐시이며 없어도 지정 경로로 자동 생성된다.

- 최신 검증 통합 아카이브와 체크섬을 `/root/rpm/output/`에서 `/root/rpm/` 바로 아래로 옮겼다. 이동 전후 SHA256을 확인했다.
- 그 후 프로젝트의 `/root/rpm/history`, `/root/rpm/tests`, `/root/rpm/output` 세 폴더를 삭제했다. 최신 설치 세트와 현재 소스, 이 plan.md의 작업 이력은 유지했다. 과거 섹션의 history/output/tests 경로는 당시의 기록이며 현재 존재 여부를 나타내지 않는다.
- 반입한 압축파일 내용, 대상 VM의 설치 파일과 부팅 설정은 변경하지 않았다. 압축파일 안에 포함된 검증 스크립트도 그대로 보존되어 있다.
- output 생성 명령은 `sudo bash prepare-debian12-kernel-offline.sh ./output`이다. 스크립트가 해당 디렉터리를 만들고 현재 저장소의 커널 및 의존성을 다시 내려받아 새 묶음과 체크섬을 생성한다. 인자를 생략하면 `/var/tmp/debian12-kernel-offline`에 생성한다.
- 필수 준비 파일은 prepare-debian12-kernel-offline.sh, kernel-offline-tools.py, kernel-boot-check.sh, install-kernel-offline.sh, collect-systemvm-state.sh, README-KO.txt 여섯 개다. tests의 두 스크립트는 있을 때만 복사하는 조건부 입력이다.
- 이 정리는 준비 프로젝트의 세 폴더에만 해당한다. 대상에서 추출한 설치 묶음은 포함된 전체 파일을 체크섬으로 검사하므로 그 안의 파일을 임의 삭제하면 검사가 실패할 수 있다.

보존된 최종 아카이브 SHA256은 `da6e1cc83c63483040fc7657093f44d0333787089e22224df657622e47ca8ac2`다. 현재 소스와 README에 재생성·정리 방법을 남겼으며, 문서 변경을 위해 기존 검증 아카이브를 다시 만들지 않는다.

### 추가 이력: 두 번째 대상의 실제 설치 및 GRUB2 갱신 완료 (2026-11-06)

사용자가 전달한 `KO2-control-1a1aacb7932`의 install 로그에서 다음을 확인했다.

- busybox 및 `linux-image-6.1.0-54-amd64=6.1.190-1` 신규 설치와 linux-image-amd64 갱신이 완료됐다.
- 신규 initramfs가 생성됐고 기존 `6.1.0-52-amd64`의 커널·initrd도 GRUB2 생성 과정에서 발견됐다.
- `/etc/kernel/postinst.d/zz-update-grub`는 기존 시스템에 설치된 Legacy 도구를 호출하여 menu.lst를 생성했다. 이는 Debian 패키지의 기존 유지관리 후크에서 수행된 작업이다. 공통 설치기는 이 파일에 의존하지 않고 뒤이어 실제 GRUB2 설정을 처리했다.
- 설정 백업 경로는 `/boot/grub/kernel-offline-backup.Ud9ZGqf3`이다. grub-mkconfig로 기존 `/boot/grub/grub.cfg`의 후보를 생성한 뒤 신규 커널/initrd·문법·기본 항목 검증이 통과하여 반영했다.
- default 0과 비어 있는 환경 블록이 확인됐으며 `Installed 6.1.0-54-amd64. No reboot performed.`로 정상 종료했다.
- os-prober 경고는 로그에 적힌 대로 다른 부팅 가능 파티션 검색을 생략한다는 뜻이다. 이 로그에는 신규 Linux 커널과 initrd가 GRUB2에 등록되고 검증된 사실이 별도로 표시되어 있다.
- 대상 설치 계획 로그: `logs/20261106T065408Z-1156192-install-plan.txt`.

남은 절차는 check-boot → 실제 부팅 선택 및 복구 콘솔 확인 → 점검 시간에 재부팅 → verify·uname·실패 서비스 및 역할별 기능 확인이다. 아직 두 번째 대상의 새 커널 실행 결과는 전달되지 않았다. 이번에는 작업 이력만 갱신했으며 통합본·프로그램·체크섬은 변경하지 않았다.

### 추가 이력: 두 번째 대상의 GRUB2 사전 점검 통과 (2026-11-06)

사용자가 전달한 `KO2-control-1a1aacb7932`의 check 결과에서 다음을 확인했다.

- `GRUB configuration strategy: grub2`, 설정 `/boot/grub/grub.cfg`, 생성기 `/sbin/grub-mkconfig`로 정상 인식했다.
- 실행 커널은 `6.1.0-52-amd64`, 목표 커널 패키지는 `linux-image-6.1.0-54-amd64=6.1.190-1`이다.
- 신규 설치 예정은 busybox와 신규 커널, 갱신 예정은 linux-image-amd64 `6.1.180-1` → `6.1.190-1`이다. 제거 예정 패키지는 0개다.
- 필요한 70.9 MB의 설치 파일은 로컬에서 준비됐고, 설치 후 추가 사용 공간은 약 411 MB로 표시됐다. `3 not upgraded`는 이번 계획에서 갱신하지 않는 패키지 수이며 실패가 아니다.
- `Local dependency and package integrity checks passed`, `Preflight passed`, `No packages installed`로 종료했다. 실제 설치는 아직 수행하지 않았다.
- 대상 로그: `logs/20261106T065327Z-1155495-check-plan.txt`.

다음 절차는 install → check-boot → 기본 부팅 선택/복구 확인 → 점검 시간에 재부팅 → verify 및 서비스 확인이다. 이 기록만 추가했으며 배포 아카이브와 체크섬은 변경하지 않았다.

> 아래 내용은 각 작업 시점의 사실과 수정 과정을 기록한 이력입니다. 과거 리비전의 검사 조건과 조치 명령을 현재 적용 절차로 사용하지 않습니다.

### 추가 이력: menu.lst 관련 Markdown 문서 점검 (2026-11-06)

- 작업 공간의 Markdown 문서 전체와 최종 통합 아카이브 내부 Markdown 문서를 확인했다.
- 현재 INSTALL.md 및 BUNDLE-USAGE.md에는 menu.lst·별도 GRUB 패치·이전 오류 조치 문서 참조가 없다. 압축파일 안에 포함된 같은 두 문서도 동일하게 확인했다.
- plan.md의 관련 문구는 실제로 겪은 오류와 수정 이력이다. 현재 정책과 당시 리비전의 정책을 구분하는 안내를 보강하고, 현재 상태 요약은 GRUB2 기준으로 정리했다.
- output에 남아 있던 이전 별도 패치의 안내 문서는 해당 패치 아카이브·체크섬과 함께 history/retired-grub-patch로 옮겼다. 내용을 변경하지 않아 이전 패치의 체크섬은 유지된다.
- history/README.md에 과거 기록임을 표시하고 현재 INSTALL.md로 연결했다. 기존 릴리스 스냅샷의 본문과 체크섬은 원본 그대로 보존했다.
- 최종 통합본의 적용 가이드는 이미 정리된 상태이므로 이번 문서 점검으로 최종 아카이브·설치 프로그램·패키지·외부 체크섬을 변경하지 않는다.

### 추가 이력: GRUB2 기준으로 가이드와 설정 선택 단순화 (2026-11-06)

사용자는 두 번째 VM 전체 검색에서도 menu.lst가 없고 grub.cfg만 있는 점을 근거로, 가이드와 프로그램에 불필요한 Legacy 메뉴 처리가 혼선을 준다고 지적했다. 해당 환경에서는 menu.lst가 필수 조건이 아니며, 앞선 VM에서 파일이 생긴 사실도 실제 Legacy 부팅의 증거는 아니다.

- INSTALL.md와 README에서 menu.lst/Legacy의 사용자 조치 설명을 제거하고 grub.cfg 생성·검사 기준으로 정리했다.
- 프로그램은 기존 grub.cfg가 있으면 해당 파일의 메뉴와 전체 문법, 필요한 도구를 검증하여 GRUB2를 우선 사용한다. 남아 있는 update-grub 실행 파일의 종류는 GRUB2 구성 선택의 근거로 사용하지 않는다.
- GRUB2 경로에서는 사용하지 않는 Legacy 메뉴를 검사·생성·갱신·백업 대상으로 삼지 않는다. 비어 있거나 오래된 해당 파일 때문에 정상 GRUB2 검사가 실패하지 않는다.
- 실제 GRUB2 설정이 잘못된 경우는 중단하며, 이를 Legacy 메뉴로 우회해 성공 처리하지 않는다. grub.cfg가 전혀 없는 실제 Legacy 전용 구성에 한해 기존 내부 호환 처리를 유지한다.
- 회귀 검사 36개를 통과했다. 이전의 '모든 형식이 동시에 맞아야 한다'는 검사를 선택된 GRUB2 설정의 유효성 검증으로 바꾸고, 사용하지 않는 파일의 미변경, update-grub 부재/알 수 없는 실행 파일과 무관한 GRUB2 처리 및 Legacy 전용 경로를 확인했다.
- 다운로드 환경의 읽기 전용 preflight도 GRUB2로 정상 선택됐다. 실제 대상 VM의 설치나 부팅 파일은 이 작업에서 변경하지 않았다.
- 준비 스크립트도 부팅 검사기의 리비전을 읽어 BOOT-CONFIG-REVISION.txt를 자동 생성하도록 반영하여 새로 만드는 묶음의 버전을 동일한 방식으로 확인할 수 있게 했다.

리비전 `20261106-grub2-primary-3`으로 최종 통합 파일을 갱신했다. 패키지 47개는 동일하며, 새 설정 선택 로직을 대상에서 적용한 뒤 재부팅/verify 및 기능 검증은 계속 필요하다. 수정 이유는 이 이력에 남기고 사용자 적용 문서는 한 가지 표준 실행 순서를 유지한다.

최종 파일 검증: **87,514,902 bytes**, SHA256 `da6e1cc83c63483040fc7657093f44d0333787089e22224df657622e47ca8ac2`. **92개 내부 파일 체크섬**, 원본 **47개 deb**, 현재 설치기·검사기·준비 소스·36개 회귀 검사 코드와 리비전 일치를 확인했다. 사용자 적용 문서에 menu.lst/Legacy 조치가 없음을 확인했다. 이전 코드와 체크섬은 `history/releases/grubfix1-before-grub2-priority-3/`에 보존했다. 아카이브 내부 plan.md는 최종 압축 해시를 기록하기 직전의 이력이다.

### 추가 이력: Legacy 실행 파일이 남은 GRUB2 전용 대상 지원 (2026-11-06)

1. 다른 대상 `KO2-control-1a1aacb7932`의 check가 `Updater is legacy but /boot/grub/menu.lst is missing/empty`로 중단됐다. 이 단계에서 패키지는 설치되지 않았다.
2. 사용자 조회 결과에서 menu.lst가 없고, 기존 grub.cfg·grubenv·i386-pc/core.img가 있음을 확인했다. grub.cfg에는 default 0과 정상적인 기존 `6.1.0-52-amd64` 커널/initrd 항목이 있다. 단순히 update-grub 실행 파일의 종류만으로 menu.lst가 필수라고 판단한 것은 부팅 도구와 구성 파일의 불일치를 충분히 지원하지 못한 검사기의 한계였다.
3. Legacy 메뉴가 실제로 없고 정상적인 기존 GRUB2 설정이 있는 경우, grub-mkconfig/grub-script-check와 기존 커널/initrd 항목 및 전체 문법을 확인한 후 GRUB2 설정 전략을 선택한다. 빈 menu.lst는 만들지 않으며, 정상 Legacy 메뉴가 있는 대상은 기존 처리를 유지한다. 비어 있거나 잘못된 설정, 인식할 수 없는 업데이터는 중단한다.
4. GRUB2 전략에서는 남아 있는 Legacy 실행 파일을 직접 실행하지 않고 검증된 GRUB2 후보를 생성하여 갱신한다. 패키지 후크가 설치 중 Legacy 메뉴를 생성하면 존재하는 두 설정을 최종 점검한다. 백업·원본 보존·기본 항목·환경 블록 검사와 MBR/EFI 비변경 원칙은 유지한다.
5. 회귀 검사를 총 32개로 확장하여 통과했다. 이번 대상과 같은 설정 선택, Legacy 실행 방지, 빈 메뉴 미생성, 잘못된 GRUB2 거절, 생성 실패 원본 보존, 패키지 후크가 뒤늦게 만든 메뉴의 검사 및 정상 GRUB2 업데이터 경로를 추가했다.
6. 다운로드 작업 환경도 같은 Legacy 실행 파일 + GRUB2 전용 구성이다. 읽기 전용 preflight 실행에서 GRUB2 구성 전략을 선택하고 정상 기존 항목을 확인했다. 호스트 부팅 파일이나 패키지는 변경하지 않았다.

부팅 처리 리비전은 `20261106-grub2-config-selection-2`로 구분하며, 같은 최종 통합 아카이브 이름으로 제공한다. 같은 파일명 때문에 이전 추출본과 섞이지 않도록 새 디렉터리에 추출하고 BOOT-CONFIG-REVISION.txt 첫 줄을 확인하도록 안내한다. 대상의 실제 설치·재부팅·verify 결과는 별도 확인이 필요하다.

배포 확인: **87,514,799 bytes**, SHA256 `7b3d5bbdc4e11e0e269200e156177c181bbf24b86f3c19bfb811fa3fec526b39`. 최종 아카이브의 **91개 내부 파일 해시**, 기존 인증 다운로드와 동일한 **47개 deb**, 현재 설치기·부팅 검사기·source·32개 회귀 검사 코드 및 새 리비전 표식을 확인했다. 이전 코드와 체크섬은 `history/releases/grubfix1-before-grub2-only-selection/`에 보존했다. 배포 아카이브 내부 plan.md는 이 최종 압축 해시를 기록하기 직전의 이력이다.

### 추가 이력: 실제 대상 커널 전환 및 verify 성공 (2026-11-06)

사용자가 전달한 `KO2-control-1a1aacb374d`의 재부팅 후 결과:

```text
Verified: running 6.1.0-54-amd64, Debian build 6.1.190-1, CVE-2026-43499 fixed since 6.1.176-1.
uname -r: 6.1.0-54-amd64
systemctl --failed: 0 loaded units listed.
```

이 대상에서 목표 커널 패키지 설치, 양쪽 GRUB 구성 점검, 실제 재부팅 후 실행 커널·Debian 빌드 검증까지 성공한 것으로 확인했다. 실패한 systemd 서비스도 없다. SSVM/CPVM/VR 또는 해당 VM이 실제 수행하는 역할의 기능 검증은 별도로 확인해야 하며, 이 출력만으로 완료 처리하지 않는다. 다른 구성의 대상에는 동일한 통합본을 사용하되 각 VM의 check와 대표 구성별 부팅·기능 검증을 수행한다.

이 기록은 사용자 전달 결과를 반영한 것이다. 배포 아카이브와 체크섬은 변경하지 않았다. 아래의 '결과 미수신' 문구는 각 과거 작업 시점의 상태다.

### 추가 이력: 실제 대상의 양쪽 GRUB 부팅 항목 점검 통과 (2026-11-06)

사용자가 전달한 KO2 대상의 최신 `check-boot` 출력에서 다음을 확인했다.

- Legacy 업데이터 출력인 `/boot/grub/menu.lst`에서 `6.1.0-54-amd64`와 일치하는 initrd 및 기본 첫 번째 항목 검사가 통과했다.
- 추가 설정 `/boot/grub/grub.cfg`도 발견하여 동일한 목표 커널/기본 첫 번째 항목 검사를 통과했다. 앞서 구버전만 남아 있던 GRUB2 메뉴 불일치가 현재 점검에서는 해소됐다.
- Legacy default는 `0`, GRUB2는 일회성 next_entry가 있으면 우선하고 그 외에는 default `0`인 구성이다. 환경 블록 조회에서는 값이 출력되지 않았으며 선택 검사가 통과했다.
- 최종 메시지는 `Boot entry check passed. No packages installed, no boot configuration changed, no reboot performed.`였다. 중복된 Validated entry 메시지는 일반 메뉴 항목 검사와 기본 첫 번째 항목 검사를 각각 수행한 결과다.

이 출력은 부팅 준비 상태의 검증이다. 설정 갱신 이후 실제 재부팅과 `verify` 통과, 실행 커널/빌드 및 서비스 기능 확인은 아직 사용자 결과를 기다린다. 이 기록만 추가했으며 통합 아카이브와 체크섬은 변경하지 않았다.

### 추가 이력: 재부팅 후 구버전 커널 실행 확인 (2026-11-06)

1. 사용자 이력에 `reboot` 실행이 있고, 이후 `verify`가 `Running 6.1.0-52-amd64; expected 6.1.0-54-amd64`로 실패했다. `/proc/version`은 Debian `6.1.180-1`이다. `systemctl --failed`는 0개였지만 이는 목표 커널로 전환됐다는 근거가 아니다.
2. 앞서 확인한 것은 Legacy 업데이터가 만든 menu.lst의 항목이었다. `update-grub` 구현은 펌웨어/디스크에 설치된 실제 부트로더나 하이퍼바이저의 커널 선택을 증명하지 않는다. 실제 GRUB2 부팅이 오래된 grub.cfg를 사용하거나 저장된 항목을 선택했을 가능성 등이 있으나, 대상 조회 결과 전에는 원인을 확정하지 않는다.
3. 대상에 `sed -n '1,220p' /boot/grub/grub.cfg`, `uptime -s`, `systemd-detect-virt`를 각각 한 명령씩 조회하도록 요청했다. 부팅 시각, 실제 설정 및 가상화 종류를 확인한 후 변경 범위를 결정한다.
4. 소스의 `grub_validate_config_set`을 추가하여 menu.lst와 grub.cfg가 함께 존재하면 둘 다 목표 커널과 일치하는 initrd 항목을 검사한다. 한쪽이 오래됐으면 check-boot/설치 후 최종 검사를 성공 처리하지 않는다. 업데이터 종류 출력도 실제 부트로더로 오인하지 않도록 `GRUB updater output type`으로 명확히 했다.
5. 부팅 선택 출력에 다른 기존 GRUB 설정의 default 및 읽기 전용 grubenv 조회를 포함했다. 설정을 실행하거나 MBR/EFI/부트로더를 자동 교체하지 않는다.
6. 기존 10개에 혼합 설정의 불일치 거절 및 단일/복수 정상 설정 검사를 추가하여 14개 회귀 검사를 통과했다. 셸 문법도 확인했다.

7. 추가로 전달된 대상 `/boot/grub/grub.cfg`의 기본값은 `0`이며 등록된 커널과 initrd가 모두 `6.1.0-52-amd64`였다. 이전에 받은 menu.lst의 `6.1.0-54-amd64`와 일치하지 않는다. 실제 부팅이 이 오래된 GRUB2 설정을 사용한 것으로 추정하며, GRUB2 메뉴 재생성으로 조치한다. 실제 펌웨어/하이퍼바이저 경로 자체를 원격 검사한 것은 아니다.
8. Legacy 업데이터와 기존 grub.cfg가 함께 있는 경우 사전 점검에서 grub-mkconfig/grub-script-check를 요구하고, 설치 후 기존 GRUB2 설정도 생성·검사하여 반영하도록 보완했다. 백업 디렉터리를 생성하고, GRUB2 후보의 목표 커널·initrd·문법·기본 선택 검증이 통과한 뒤 기존 파일을 교체한다. 실패한 후보는 원본 grub.cfg를 덮어쓰지 않는다.
9. 기본 첫 번째 항목이 구버전인 경우, 수동 고정 default/saved 설정 또는 next_entry가 재정의하는 경우 성공 처리하지 않고 명시적 검토를 요구한다. 환경 블록은 조회만 하며 자동 삭제/수정하지 않는다. grub-install, MBR/EFI 재설치 및 자동 재부팅은 수행하지 않는다.
10. 회귀 검사를 총 24개로 확장해 통과했다. 실제 grub-editenv의 일회성 선택 값 거절과 비수정, GRUB2 생성 실패·잘못된 커널·문법 오류·saved 기본값 후보의 원본 보존, 성공 시 이전 설정 백업 및 파일 모드 보존을 검사했다. 이 검사들은 임시 경로에서 수행했으며 호스트 /boot는 변경하지 않았다.

같은 최종 통합 아카이브 파일명으로 위 보완을 반영하고 내부/외부 체크섬을 갱신했다. 사용자 대상은 새 커널을 재설치할 필요 없이 기존 grub.cfg를 백업하고 grub-mkconfig로 갱신한 뒤 문법·메뉴·환경 블록을 확인하여 재부팅/verify할 수 있다. 조치 절차는 별도의 오류 문서를 만들지 않고 INSTALL.md에 포함했다.

배포 반영 확인: 내부 리비전 `20261106-dual-grub-sync-1`, **87,511,636 bytes**, SHA256 `7137ee7cdc07e7cd39a8a46946a9e3a52389b4d96dfaa84787f06fb012435650`. 통합 아카이브의 **90개 내부 파일** 체크섬, 원본과 동일한 **47개 deb**, 수정 설치기·부팅 검사기의 source 일치, 24개 회귀 검사 코드 포함 및 셸/가이드 문법을 확인했다. 이전 설치기/검사기와 체크섬 스냅샷은 `history/releases/grubfix1-before-dual-config-sync/`에 보존했다. 대상 VM의 실제 부팅 성공을 대신하는 검증은 아니며 사용자 조치 후 verify 결과를 기다린다.

### 추가 이력: 최종 통합본 기준으로 문서 정리 (2026-11-06)

사용자가 별도의 GRUB 오류 조치 문서가 최종 적용 절차에 혼선을 줄 수 있다고 알려, `INSTALL.md`를 최종 통합본의 단일 적용 절차로 정리했다. 설치 프로그램 변경 이유와 검증 결과는 이 plan.md에 유지한다.

- `GRUB오류조치.md`는 `history/documentation/GRUB오류조치-이전패치절차.md`로 옮겨 이전 작업 기록으로 보존한다.
- 최종 통합 아카이브에는 해당 오류 조치 문서와 별도 패치 절차를 포함하지 않는다.
- `INSTALL.md`에서는 과거 호스트 출력·초기 아카이브·패치 적용 분기를 제거하고, 최종 통합본의 표준 실행 순서만 안내한다.
- `BUNDLE-USAGE.md`는 최종 파일명과 INSTALL.md 위치를 안내하는 짧은 문서로 정리한다.
- README의 이전 오류·작은 패치 안내를 제거한다.
- 통합 아카이브의 사용자 안내 문서와 내부 체크섬을 갱신하고, 같은 최종 파일명으로 문서 정리본과 새 외부 체크섬을 제공한다. 이전 문서판 아카이브와 체크섬은 history/releases에 보존한다.
- 설치기·부팅 검사기·47개 deb는 기존 통합본의 검증된 파일 그대로 사용한다. 이미 반입·설치한 VM에 문서 정리만을 위한 재설치나 재반입은 필요하지 않다.

문서 정리본 최종 검증: **87,504,368 bytes**, 내부 체크섬 **88개 파일** 일치, **47개 deb 및 7개 셸 스크립트 해시 보존**, 사용자 적용 문서의 이전 오류 조치/패치 참조 제거와 Bash 예제 문법을 확인했다. 외부 체크섬도 함께 갱신했다. 이전 문서판의 SHA256 `e879d8abbaaf3a6e6688734d64813e48a1ff34bf23c10a9e66349a18ce330ed9`와 아카이브는 `history/releases/grubfix1-before-documentation-cleanup/`에 보존했다. 현재 아카이브 내부 plan.md는 최종 압축 해시를 기록하기 직전의 문서 정리 이력이다.

### 추가 이력: 수정 통합본으로 실제 대상 설치 단계 완료 (2026-11-06)

사용자가 전달한 `KO2-control-1a1aacb374d`의 `...-grubfix1` 실행 로그에서 check 및 install의 정상 완료를 확인했다.

- APT 계획: `0 upgraded, 0 newly installed, 0 to remove`. 목표 커널·메타패키지·busybox는 이전 작업에서 이미 설치되어 추가 패키지 변경은 없었다.
- 실행 커널은 아직 `6.1.0-52-amd64`이며, 설치된 목표 커널은 `6.1.0-54-amd64=6.1.190-1`이다.
- install은 신규 initramfs와 GRUB Legacy `menu.lst`를 다시 생성했다.
- 수정 검사기가 `GRUB type: legacy`, `/boot/grub/menu.lst`, 신규 커널과 일치하는 initrd를 포함한 메뉴 항목 및 `default 0`을 확인했다.
- 최종 메시지: `Installed 6.1.0-54-amd64. No reboot performed.` 기존 GRUB2 전용 검사 오류는 이 대상의 수정본 실행에서 해소됐다.
- 남은 절차: 실제 콘솔의 부팅 선택을 확인하고 점검 시간에 재부팅한 뒤 `verify`, 실행 커널/빌드 및 서비스 기능을 확인한다. 대상의 재부팅·verify 완료 결과는 아직 전달되지 않았다.

이 기록은 사용자 전달 로그의 해석이며, 이 작업 공간에서 대상 VM을 원격 설치하거나 재부팅하지 않았다. 배포 아카이브 및 체크섬은 변경하지 않았다.

### 추가 이력: GRUB 수정 통합 아카이브 (2026-11-06)

사용자가 원래 tar.gz를 다시 풀어 설치하면 되는지 문의하여, 기존 원본에 수정 전 설치기가 남아 있음을 설명했다. 별도 작은 패치 없이 반입·추출하여 사용할 수 있도록 `debian12-kernel-amd64-20261106T045535Z-TS4fvBkX-grubfix1.tar.gz` 통합본을 생성했다.

통합본은 별도의 동일 이름 추출 디렉터리를 사용하여 기존 원본 추출본과 섞이지 않게 한다. 기존 인증 다운로드한 47개 deb를 원본 체크섬과 대조해 재사용하고, 수정 설치기·`kernel-boot-check.sh`·최신 재생성 소스·회귀 검사·한국어 안내를 함께 포함한다. 변경된 파일에 맞춘 내부 SHA256SUMS와 새 아카이브 체크섬을 생성한다. 원본 아카이브 및 원본 체크섬은 변경하지 않는다.

`BUNDLE-USAGE.md`를 추가하고 `INSTALL.md`의 기본 반입 파일명을 수정 통합본으로 갱신했다. 이미 목표 커널 설치가 완료된 KO2 대상은 통합본에서 `check-boot`를 먼저 실행하여 재설치 없이 확인하는 절차로 안내한다.

통합본 최종 검증:

- 크기: **87,509,923 bytes (약 83.46 MiB)**.
- SHA256: `e879d8abbaaf3a6e6688734d64813e48a1ff34bf23c10a9e66349a18ce330ed9`.
- 내부 체크섬 **87개 파일** 일치 및 원본 **47개 deb 해시 전부 동일**함을 확인했다.
- 실제 수정 설치기, 부팅 검사기 및 최신 준비 소스가 포함되어 있음을 바이트 비교로 확인했다.
- 아카이브가 독립된 `...-grubfix1/` 경로로 추출되며 위험한 상위/절대 경로나 링크가 없음을 확인했다.
- 포함된 셸 스크립트와 가이드 명령의 Bash 문법을 확인했다.
- 외부 검증 기록: `output/grubfix1-verification.txt`.
- 아카이브 내부 plan.md는 최종 압축 해시를 기록하기 직전의 작업 이력이다. 이 작업에서 대상 패키지 설치나 재부팅은 수행하지 않았다.

### 추가 이력: 실제 대상 설치 로그와 GRUB Legacy 검사 수정 (2026-11-06)

1. 사용자가 전달한 `KO2-control-1a1aacb374d`의 check 로그에서 실행 커널 `6.1.0-52-amd64`, 기존 메타패키지 `6.1.180-1`, 목표 `6.1.190-1`의 로컬 의존성 점검 통과를 확인했다.
2. 후속 install 로그에서 신규 커널 및 busybox 설치, 메타패키지 갱신, initramfs 생성, GRUB `menu.lst` 갱신을 확인했다. 설치기 마지막 단계는 `grub.cfg`만 검사하여 `New kernel absent from GRUB`로 실패했다. 기존 설치기의 GRUB2 전용 검사 오류였다.
3. 사용자에게 조회 명령을 요청했다. 여러 명령이 한 줄로 합쳐져 생긴 dpkg 구문 오류를 설명하고, `sed -n '1,180p' /boot/grub/menu.lst` 한 명령으로 재확인했다. 이 구문 오류를 dpkg 패키지 손상으로 판단하지 않았다.
4. 전달된 메뉴에서 `default 0`, 첫 신규 커널 항목의 `/vmlinuz-6.1.0-54-amd64`와 `/initrd.img-6.1.0-54-amd64`, 기존 `6.1.0-52-amd64` 복구 항목을 확인했다. 실제 디스크/펌웨어·하이퍼바이저가 선택하는 부트로더는 콘솔에서 확인해야 한다.
5. `kernel-boot-check.sh`를 추가했다. 실제 `update-grub` 구현을 읽어 Legacy `menu.lst` 또는 GRUB2 `grub.cfg`를 선택한다. 두 파일이 동시에 존재해도 존재 여부만으로 고르지 않는다. 알 수 없는 업데이터 또는 출력 파일 누락은 설치 전 중단한다.
6. 신규 커널과 일치하는 initrd가 **같은 실제 메뉴 항목**에 있는지 검사한다. 주석·제목의 버전 문자열, 서로 다른 항목의 kernel/initrd는 통과시키지 않는다. `grub-script-check`는 GRUB2 설정에만 적용한다.
7. 설치기에 읽기 전용 `check-boot` 모드를 추가했다. 이미 설치한 커널·dpkg 상태·파일·부팅 항목을 확인하며 패키지 재설치, update-grub, initramfs 생성 및 재부팅을 하지 않는다. 준비 스크립트는 새 보조 검사기를 묶음 및 source에 포함하도록 수정했다.
8. `tests/test_grub_boot.py`의 10개 회귀 검사를 통과했다. Legacy+오래된 grub.cfg, GRUB2+오래된 menu.lst, 잘못된 주석/제목, 다른 항목의 initrd, 구버전 initrd, 중첩 메뉴, Legacy에 GRUB2 문법 검사를 실행하지 않는 동작 및 알 수 없는 업데이터 거절을 검사했다.
9. 다운로드 VM에서도 Legacy 업데이터와 grub.cfg만 남은 혼합 구성을 확인했다. 수정 검사기는 menu.lst 누락을 설치 전 거절했다. 이 VM의 부팅 설정을 자동 변경하지 않았다.
10. 기존 47개 deb를 재전송하지 않아도 되는 작은 수정 묶음을 생성했다. 실제 묶음 복사본에 적용하여 내부 체크섬 통과, 47개 deb 해시 보존, 손상된 원본 메타데이터의 교체 전 거절을 검증했다. 기존 원본 아카이브와 체크섬은 유지했다.

수정본:

- `output/systemvm-grub-check-fix-1.tar.gz` (14,713 bytes)
- `output/systemvm-grub-check-fix-1.tar.gz.sha256`
- SHA256: `afb72a1ef9e47ea8fec3d51f7c8708dd68d0f15bc5f2d430302542b86a739073`
- 적용기 원본: `apply-grub-check-fix.sh`
- 조치 안내: `GRUB오류조치.md`; 기존 `INSTALL.md`에도 수정본 적용과 check-boot 절차를 반영했다.
- 기존 잘못된 검사기 사본: `history/install-kernel-before-grubfix1.sh`

패치 적용기는 기존 묶음 및 패치의 무결성을 검사한 후 변경 대상 스크립트/안내 파일을 백업하고 해당 파일의 체크섬만 갱신한다. 무결성 오류를 숨기기 위해 deb 체크섬을 새로 신뢰하도록 갱신하지 않는다. 패키지·부팅 파일·실행 커널은 변경하지 않는다.

대상 VM에서 남은 절차: 수정본 적용 → `bash install-kernel.sh check-boot` → 콘솔/부팅 선택 확인 → 점검 시간에 재부팅 → `verify` 및 서비스 기능 검증. 현재 대화에는 대상의 재부팅/verify/서비스 검증 완료 결과가 없다.

공식 근거:

- https://manpages.debian.org/bookworm/grub-legacy/update-grub.8.en.html
- https://manpages.debian.org/bookworm/grub2-common/update-grub.8.en.html
- https://manpages.debian.org/bookworm/grub-common/grub-script-check.1.en.html

추가 문서 이력 (2026-11-06): 사용자가 전달한 현재 VM의 `check` 성공 로그를 반영하여 `INSTALL.md`를 작성했다. 현재 VM에서 `verify`를 먼저 수행하는 분기, 구버전 대상의 반입·점검·설치·재부팅·역할별 검증, 오류 조치 및 여러 대상 상태를 합쳐 재생성하는 방법을 포함한다. 전달된 로그는 목표 커널 패키지가 이미 설치되었음을 보여주지만, 해당 VM의 실행 빌드 검증 결과는 아직 전달되지 않았다. 문서만 추가했으며 기존 전송 아카이브와 체크섬은 변경하지 않았다.

빈 상태의 Depends/Pre-Depends 계산은 다운로드 VM에 이미 설치된 의존성의 누락을 방지한다. 모든 대체 의존성 공급자, 설치 조합, 역의존성, hold/pin, DKMS 및 부트로더 구성을 보장하지 않는다. 실제 대상 패키지 상태를 추가로 반영하고 각 VM에서 `check`를 통과해야 한다. 서로 다른 템플릿/패키지 구성마다 복제본 설치 및 재부팅 검증이 필요하다.

SystemVM은 제품 템플릿에서 생성된다. 기존 VM을 수정해도 이후 재생성되는 VM에는 자동 반영되지 않으므로 템플릿 갱신은 별도로 검증한다.

참고:

- https://manpages.debian.org/bookworm/apt/apt.conf.5.en.html
- https://manpages.debian.org/bookworm/apt/apt-get.8.en.html

2026-11-10: Renamed Markdown guides to English filenames and updated document links and build references.
