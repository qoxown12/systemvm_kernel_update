# Rocky Linux 9에서 제품 가상머신 원격 커널 적용

작성일: 2026-11-06

`deploy-systemvm-kernel.sh`를 실행 VM에 두고 `-k` SSH 키 경로, `-f` 패치 tar.gz, `-i` 대상 IP, `-p` SSH 포트를 지정합니다. 접속 계정은 `cloud`입니다. **기본 실행은 점검·설치·check-boot가 통과하면 대상 VM을 자동 재부팅하고 재접속하여 검증합니다.**

| 구분 | 운영체제와 역할 |
| --- | --- |
| 실행 VM | Rocky Linux 9. SSH/SCP 전송, 검증 및 진행 제어 |
| 대상 VM | Debian 12 / amd64 제품 SystemVM 또는 템플릿 기반 관리형 Kubernetes 노드. 커널 설치·재부팅·서비스 확인 |

Rocky 실행 VM에서는 Debian 패키지를 설치하지 않습니다. 커널·의존성 수집과 tar.gz/ISO 빌드는 기존 [BUILD.md](BUILD.md)의 Debian 12 준비 환경을 사용합니다.

## 준비 파일과 권한

실행 VM에는 다음 파일이 필요합니다.

```text
deploy-systemvm-kernel.sh
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz.sha256
```

패치 파일은 `-f`로 명시합니다. 같은 경로에 `<패치 파일명>.sha256`도 있어야 합니다. 기존 tar.gz를 그대로 사용하며 설치기 수정이나 재압축은 필요하지 않습니다.

Rocky Linux 9 실행 VM에서 기본 저장소의 Bash, Python 3.9 이상, OpenSSH 클라이언트(`ssh`, `scp`), coreutils, gawk를 준비합니다.

```bash
sudo dnf install -y bash python3 openssh-clients coreutils gawk
python3 --version
ssh -V
```

Rocky 9 기본 Python 3.9를 사용할 수 있습니다. 별도 Python 3.11 설치나 pip 패키지는 필요하지 않습니다. 아카이브 해시는 파일을 나누어 읽는 표준 SHA256 계산으로 검사합니다. 대상 VM에는 이 검증을 위한 Python을 추가 설치하지 않습니다. Rocky의 기본 Python·OpenSSH 구성은 [공식 릴리스 문서](https://docs.rockylinux.org/releases/release_notes/9_0/)를 참고합니다.

실행 VM에서는 키 파일을 읽을 수 있고 현재 디렉터리에 로그를 만들 수 있는 계정이면 됩니다. 로컬 root는 필수가 아닙니다. 대상의 `cloud` 계정은 키로 접속할 수 있고 **비밀번호 입력 없이 `sudo -n`으로 root의 Bash를 실행**할 수 있어야 합니다. 스크립트가 sudo 정책이나 키 권한을 변경하지는 않습니다. 암호화한 키는 실행 전 ssh-agent에 등록하여 비대화형 접속이 가능하게 준비합니다.

키의 내용은 읽어서 로그에 출력하거나 대상으로 전송하지 않습니다. SSH 클라이언트의 인증에만 사용합니다. 처음 보는 SSH 호스트 키는 등록하며, 기존 호스트 키가 바뀌면 접속을 거절합니다.

## 실행 명령

전체 적용:

```bash
bash deploy-systemvm-kernel.sh \
  -k /path/to/systemvm_ssh_key \
  -f ./output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz \
  -i 192.0.2.10 -p 2222
```

예시 IP와 키·패치 경로, 포트를 실제 값으로 바꿉니다. 옵션 순서는 바꿔도 됩니다. SSH 포트는 기본값 없이 `-p`로 지정합니다.

| 옵션 | 입력값 |
| --- | --- |
| `-k` / `--key` | 실행 VM의 SSH 개인키 경로 |
| `-f` / `--archive` | 실행 VM에 있는 패치 tar.gz 경로 |
| `-i` / `--ip` | 대상 VM의 IPv4 또는 IPv6 주소 |
| `-p` / `--port` | 대상 VM의 SSH 포트 |
| `--scp-legacy` | 대상에서 SFTP를 사용할 수 없을 때 `scp -O` 전송을 명시적으로 선택 |

한 줄로 실행하는 예:

```bash
bash deploy-systemvm-kernel.sh -k /path/to/systemvm_ssh_key -f /home/cloud/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz -i 192.0.2.10 -p 2222
```

먼저 원격 점검만 실행하려면:

```bash
bash deploy-systemvm-kernel.sh \
  -k /path/to/systemvm_ssh_key \
  -f ./output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz \
  -i 192.0.2.10 -p 2222 --check-only
```

`--check-only`도 파일 전송·압축 해제·로그 생성을 수행합니다. 패키지 설치, 부팅 설정 변경, 재부팅은 수행하지 않습니다. 전체 적용은 새 실행으로 진행합니다.

## 제품 가상머신 식별 조건

전송 전에 대상에서 다음을 모두 확인합니다.

1. Debian 12, amd64이며 systemd가 동작한다.
2. `systemd-detect-virt --vm`으로 가상머신이 확인된다.
3. 제품 릴리스 정보, 템플릿 초기화 스크립트, `/var/cache/cloud/cmdline` 역할 캐시가 존재하고 비어 있지 않다.
4. cmdline의 `type=`이 `secstorage`, `consoleproxy`, `router`, `vpcrouter`, `dhcpsrvr`, `internallbvm`, `cksnode` 중 하나이며 하나의 역할만 지정되어 있다.
5. `cksnode`는 추가로 `kubelet.service` 또는 `etcd.service`가 로드되어 있어야 한다. kubelet이 있으면 Kubernetes 노드로, kubelet 없이 etcd가 있으면 전용 etcd 노드로 서비스 확인 기준을 잡는다.
6. `cloud`의 비대화형 sudo 및 필요한 원격 명령을 사용할 수 있다.

제품 템플릿과 역할 정보를 함께 확인합니다. 일반 사용자 VM이나 템플릿·역할 증거가 없는 Kubernetes 노드는 전송 전에 중단합니다. 커스텀 템플릿에서 식별 파일이 다르면 실제 템플릿을 확인해야 하며 강제로 검사를 생략하는 옵션은 제공하지 않습니다.

`type=cksnode`는 관리형 Kubernetes 노드를 나타냅니다. 해당 유형은 제품 SystemVM 템플릿을 기반으로 배포된 노드이며, `cloud` 계정으로 접속합니다.

`cksnode`를 SSVM/CPVM/VR과 별도로 분류하여 지원하는 스크립트 리비전은 `20261106-rocky9-cks-1`입니다. 기존 파일을 교체한 뒤 `bash deploy-systemvm-kernel.sh --help`의 Revision 값을 확인합니다. 이전 리비전의 `Unknown or ambiguous SystemVM type` 오류가 났을 때에는 전송·설치·재부팅이 수행되지 않았습니다.

이 검사는 게스트 내부 증거를 사용합니다. 관리 API의 VM UUID 대조는 수행하지 않습니다. cmdline은 인증 정보가 포함될 수 있으므로 전체 내용을 출력하거나 실행하지 않고 `type=`만 읽습니다.

## 단계별 동작

| 단계 | 수행 내용 |
| --- | --- |
| 1 | 로컬 tar.gz 외부 체크섬, 내부 전체 파일 해시, 단일 루트와 안전한 경로 검증 |
| 2 | SSH·sudo·제품 가상머신 역할·OS·아키텍처 확인 및 VM 식별값과 boot ID 기록 |
| 3 | cloud 홈의 임시 디렉터리로 tar.gz와 원격 작업기만 SCP 전송 |
| 4 | root 전용 작업본을 확보하고 전송 해시 확인, 원격 systemd 작업 시작 |
| 5 | 압축 해제와 내부 무결성 확인 → check → install → check-boot |
| 6 | 위 단계가 모두 통과한 경우에만 재부팅 1회 예약 |
| 7 | 같은 IP·포트로 재접속, 이전과 다른 boot ID 및 동일 VM 식별값 확인 |
| 8 | 기존 설치기의 verify, dpkg audit, 실패 유닛과 필수 서비스 확인 |

파일 전송은 Rocky 9의 `scp` 기본 전송 방식인 SFTP를 사용합니다. 대상에서 SFTP를 사용할 수 없는 구성일 때 `--scp-legacy`를 추가하면 `scp -O`를 사용합니다. 해당 경우 대상에 scp 명령도 있어야 합니다. 전송 실패 시 자동으로 프로토콜을 바꾸거나 보안 정책을 변경하지 않습니다. 옵션의 근거는 [Red Hat OpenSSH 문서](https://www.redhat.com/de/blog/openssh-scp-deprecation-rhel-9-what-you-need-know)를 참고합니다.

```bash
bash deploy-systemvm-kernel.sh \
  -k /path/to/systemvm_ssh_key \
  -f ./output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz \
  -i 192.0.2.10 -p 2222 --check-only --scp-legacy
```

업로드한 원격 작업기는 해시 확인 후 root 소유 파일로 실행합니다. 실제 APT/dpkg 설치는 SSH와 분리된 systemd 작업으로 수행합니다. 실행 중인 원격 작업 간에는 잠금을 사용합니다.

동일 VM 식별값은 machine ID, 접근 가능한 DMI UUID, SystemVM 역할을 조합한 해시입니다. 준비 중 다른 VM으로 바뀌거나 부팅이 바뀌면 중단합니다. SSH가 연결된다는 사실만으로 재부팅 완료로 판단하지 않습니다.

각 단계의 오류 시 다음 단계로 진행하지 않습니다. 설치나 check-boot가 실패하면 재부팅을 예약하지 않습니다. 재부팅 후 검증 실패 시 자동 재설치, 서비스 재시작, 두 번째 재부팅은 수행하지 않습니다.

## 재부팅 후 서비스 확인 범위

커널 ABI, 설치된 Debian 패키지 버전, 실제 실행 중인 Debian 커널 빌드를 기존 설치기의 verify로 확인합니다. 추가로 다음 조건을 확인합니다.

- `dpkg --audit` 결과에 오류가 없다.
- `systemctl --failed` 결과가 비어 있다. 업데이트 전부터 실패한 유닛이 남아 있어도 성공으로 처리하지 않는다.
- 업데이트 전에 `running`이던 비일시적 서비스가 다시 활성화되어 있다.
- `ssh.service`가 활성 상태다. SSVM/CPVM은 `cloud.service`도 확인한다.
- 관리형 Kubernetes 노드는 kubelet 또는 전용 etcd 서비스를 확인하고, 재부팅 전에 실행 중이던 containerd·Docker 등 런타임의 복귀도 기존 서비스 목록으로 확인한다. SSVM/CPVM용 cloud.service를 요구하지 않는다.
- SystemVM은 `/var/cache/cloud/enabled_svcs`에 선언되어 있고 해당 VM에 로드된 서비스가 활성 상태다. Kubernetes 노드에는 미사용 템플릿 역할의 목록을 적용하지 않는다.

일시적인 systemd 작업 서비스는 복귀 대상에서 제외합니다. 부팅·서비스 시작은 제한 시간 동안 기다린 뒤 실패 내역을 남깁니다. 이전에 실행 중이던 서비스가 재부팅 후 의도적으로 종료되는 구성이라면 실패 보고를 검토해야 합니다.

관리 서버와의 통신 및 역할별 실제 기능은 별도로 확인합니다. SSVM의 템플릿·ISO 전송, CPVM의 콘솔, VR의 DHCP/DNS/NAT 등은 사용 중인 기능에 맞춰 확인합니다. 관리형 Kubernetes 노드는 관리자 kubeconfig를 가진 환경에서 다음을 확인합니다.

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

이 스크립트는 Kubernetes cordon/drain/uncordon을 실행하지 않습니다. 노드별 점검·재부팅 순서와 워크로드 이동은 클러스터 운영 절차에서 관리합니다. kubelet 서비스의 활성 상태만으로 Node Ready나 전체 Pod의 정상 상태를 판정하지 않습니다.

## 시간 제한과 재검증

기본 대기 시간은 원격 설치 1,800초, 재부팅·SSH 복귀 900초, systemd 시작 및 서비스 확인 각각 180초입니다. 필요하면 늘릴 수 있습니다.

```bash
bash deploy-systemvm-kernel.sh \
  -k /path/to/systemvm_ssh_key \
  -f ./output/debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz \
  -i 192.0.2.10 -p 2222 \
  --install-timeout 3600 --reboot-timeout 1200 --service-timeout 300
```

**컨트롤러 종료나 SSH 단절은 이미 시작된 원격 설치 작업을 취소하지 않습니다.** 설치 대기 시간이 초과되면 원격 상태와 로그를 먼저 확인합니다. 새 전체 적용을 즉시 반복하지 않습니다.

실행 시작 시 출력되는 `Run:` 값을 보관합니다. 예를 들어 이전 apply 실행이 `20261106T100000Z-12abCD34`였고 재부팅 후 검증만 다시 하려면:

```bash
bash deploy-systemvm-kernel.sh -k /path/to/systemvm_ssh_key -i 192.0.2.10 -p 2222 \
  --verify-only 20261106T100000Z-12abCD34
```

이 모드에는 로컬 tar.gz가 필요하지 않습니다. 기존 원격 실행의 VM 식별값·boot ID·설치 묶음·서비스 기준을 사용하여 검증만 수행합니다. 전송·설치·재부팅은 하지 않습니다. 재부팅이 실제 완료되지 않았거나 check-only 실행 ID를 지정하면 실패합니다.

## 로그와 성공 판정

실행 VM의 현재 디렉터리에 `systemvm-rollout-<실행ID>-<식별자>/`가 생성됩니다.

| 파일 | 내용 |
| --- | --- |
| `controller.log` | 접속·전송·단계·재부팅 대기·검증 결과 |
| `remote.log` | 종료 시 수집한 원격 설치·검증 및 서비스 자료 |
| `remote-worker.sh` | 해당 실행에 사용한 원격 작업기 원본 |
| `last-ssh-error.txt` | 마지막 폴링 접속 오류 |
| `log-fetch-error.txt` | 원격 로그를 가져오지 못한 경우의 오류 |

대상 VM의 root 작업 경로는 `/var/lib/systemvm-kernel-rollout/<실행ID>/`입니다.

```text
status                       # 진행 상태 또는 VERIFIED / COMPLETE_CHECK / FAILED
error.txt                    # 실패 단계와 종료 코드
run.log                      # 추출·check·install·check-boot·재부팅 예약
verify.log                   # 재부팅 후 커널·서비스 검증
services-before.txt          # 업데이트 전 실패 서비스
required-services.txt        # 재부팅 후 활성 상태여야 하는 서비스
failed-after.txt             # 재부팅 후 실패 유닛
inactive-after.txt           # 복귀하지 않은 필수 서비스
extracted/<묶음이름>/logs/    # 기존 설치기가 남긴 APT 계획·설치 로그
```

종료 코드 0이며 전체 적용에서 `[8/8] SUCCESS`와 원격 `status=VERIFIED`가 확인되면 커널·로컬 서비스 검증까지 통과한 것입니다. check-only의 `COMPLETE_CHECK`는 설치 완료를 의미하지 않습니다. 로그 수집 시 대상에 접속할 수 없으면 원격 작업 경로에 자료가 남습니다.

전체 적용 전에 복구 가능한 백업과 콘솔, 재부팅 가능한 점검 시간을 준비하고 대표 SystemVM 복제본에서 검증합니다. 이 스크립트는 한 번에 입력한 VM 한 대를 처리합니다.

## 참고 근거

- [Debian systemd-run](https://manpages.debian.org/bookworm/systemd/systemd-run.1.en.html): SSH와 분리된 서비스 및 재부팅 타이머 실행.
- [Debian systemctl](https://manpages.debian.org/bookworm/systemd/systemctl.1.en.html): 부팅·서비스 상태 확인.
