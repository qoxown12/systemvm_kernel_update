# Koral · 공유FS 보안 취약점 업데이트 작업가이드

## 1 작업 개요

Debian 12 amd64 기반 Koral Kubernetes 노드와 공유파일시스템(공유FS) VM에 오프라인 보안 업데이트 번들을 적용합니다. CCVM에서 SSH로 대상 VM 한 대씩 배포하며, 스크립트가 패키지 설치와 부팅 설정 검증을 마친 VM을 자동 재기동합니다. 재접속 후 해당 VM의 서비스 정상 동작을 확인하고 다음 대상으로 넘어갑니다.

| 항목 | 배포 목표 |
| --- | --- |
| Linux 커널 · CVE-2026-99362 | 실행 커널 `6.12.117+deb12-amd64`, Debian 패키지 `6.12.117-1~deb12u1` |
| OpenJDK 17 · CVE-2026-91403 | `openjdk-17-jre-headless` 패키지 `17.0.21.1+2-1~deb12u1` |
| CA 인증서 | `ca-certificates` 패키지 `20250419~deb12u2` |

번들의 Bookworm용 6.12 커널은 Debian의 CVE-2026-99362 수정 버전입니다. CVE-2026-43499는 Debian이 안내하는 6.12 계열 수정 버전(`6.12.86-1`)을 기준으로 함께 추적합니다. 별도 JDK나 다른 Java 런타임을 사용하는 서비스는 실제 실행 경로와 해당 배포판의 수정 버전을 확인합니다. [CVE-2026-99362](https://security-tracker.debian.org/tracker/CVE-2026-99362) · [CVE-2026-43499](https://security-tracker.debian.org/tracker/CVE-2026-43499) · [CVE-2026-91403](https://security-tracker.debian.org/tracker/CVE-2026-91403)

### 1.1 6.12 전환 및 CVE-2026-99362 확인

- 본 번들은 Bookworm용 6.12 메타패키지 `linux-image-6.12-amd64`를 설치합니다. 기존 6.1 커널은 부팅 복구에 사용할 수 있도록 유지합니다.
- 운영 배포 전에 대표 Koral 노드와 공유FS VM에서 6.12 부팅 및 서비스 호환성을 확인합니다. 대상 VM의 실제 패키지 상태에 대한 설치 가능 여부는 2절의 사전 점검으로 확인합니다.
- 공유FS에서 커널 NFS 서버를 운영하는 경우 패치 적용 전까지 신뢰된 클라이언트로만 접근을 제한합니다. 업데이트 후에는 실행 커널 버전과 NFS 클라이언트 재접속 및 읽기·쓰기를 확인합니다.

## 2 업데이트 작업 절차

### 2.1 업데이트 사전 준비

| 항목 | 내용 |
| --- | --- |
| 작업 서버 및 배치 경로 | CCVM의 `/opt/rpm/` |
| 배포 스크립트 | `deploy-systemvm-kernel.sh` |
| 오프라인 번들 | `debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz` |
| 체크섬 | `debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz.sha256` |
| Koral SSH 접속 | `cloud` 계정, 기존 관리 SSH 키, 비대화형 sudo |
| 공유FS SSH 접속 | `root` 계정, 대상 VM에 허용된 비밀번호 SSH 접속 |

- 대상별 IP·포트·역할, 콘솔 접근과 복구 방법을 확인합니다. 아래 명령의 IP와 포트는 작업 예시이므로 실제 대상 값으로 바꿉니다.
- Koral은 노드 및 Pod 상태와 컨트롤 플레인·etcd 가용성을 확인합니다. 필요 시 운영 절차에 따라 노드를 cordon하고 워크로드를 이동합니다.
- 공유FS는 연결된 클라이언트, 공유 볼륨, 의존 애플리케이션을 확인합니다. 재기동 전에 쓰기 작업을 중지하고 재기동 후 재개하는 순서를 정합니다.
- 대상 VM에서 OS·아키텍처, 실행 커널, 설치 패키지와 기존 실패 서비스 상태를 기록합니다. Java 서비스가 있다면 사용 중인 런타임도 기록합니다.

### 2.2 업데이트 파일 준비

CCVM에서 세 파일을 같은 디렉터리에 원래 이름으로 배치하고 체크섬과 스크립트 리비전을 확인합니다.

```bash
cd /opt/rpm
sha256sum -c debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz.sha256
bash deploy-systemvm-kernel.sh --help
```

체크섬 결과가 `OK`인지 확인합니다. 저장소에 포함된 스크립트의 리비전은 `20261112-skip-service-health-11`입니다.

### 2.3 Koral 노드 업데이트

CCVM에서 대상 노드 한 대를 지정해 사전 점검을 실행합니다. SSH 키 경로도 운영 환경에 맞게 확인합니다.

```bash
cd /opt/rpm
bash deploy-systemvm-kernel.sh \
  -k /var/cloudstack/management/.ssh/id_rsa \
  -f debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz \
  -i 10.10.1.59 -p 2222 --check-only
```

사전 점검은 SSH 접속, 대상 식별, 번들 전송·압축 해제 및 설치 가능 여부를 확인합니다. `SUCCESS: AbleStack VM check passed.`를 확인한 뒤 같은 대상에 업데이트를 실행합니다.

```bash
bash deploy-systemvm-kernel.sh \
  -k /var/cloudstack/management/.ssh/id_rsa \
  -f debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz \
  -i 10.10.1.59 -p 2222
```

역할 표시 `SYSTEMVM_ROLE=cksnode`와 `ABLECLOUD_VM_CLASS=cksnode`를 확인합니다. 자동 재기동 후 4절과 5절의 완료 조건을 충족하면 다음 노드를 진행합니다.

### 2.4 공유FS VM 업데이트

클라이언트 및 애플리케이션의 작업 중지를 확인한 후 CCVM에서 사전 점검을 실행합니다. 프롬프트가 표시되면 대상 VM의 root 비밀번호를 입력합니다.

```bash
cd /opt/rpm
bash deploy-systemvm-kernel.sh -t sharedfs \
  -f debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz \
  -i 10.10.254.39 -p 22 --check-only
```

`SUCCESS: AbleStack VM check passed.`를 확인한 뒤 같은 대상에 업데이트를 실행하고 프롬프트에 root 비밀번호를 입력합니다.

```bash
bash deploy-systemvm-kernel.sh -t sharedfs \
  -f debian12-kernel-amd64-20261127T062911Z-z3TZRSxQ.tar.gz \
  -i 10.10.254.39 -p 22
```

역할 표시 `SYSTEMVM_ROLE=sharedfsvm`과 `ABLECLOUD_VM_CLASS=sharedfs`를 확인합니다. 자동 재기동 후 4절과 5절의 완료 조건을 충족하면 클라이언트와 애플리케이션을 정상 운영 상태로 전환합니다.

## 3 대상별 업데이트 진행 순서

| 순서 | 작업 대상 | 작업 내용 |
| --- | --- | --- |
| 1 | CCVM 및 전체 작업 대상 | 배포 파일·체크섬, 접속, 작업 전 상태 확인 |
| 2 | Koral 노드 한 대 | 워크로드 이동, 사전 점검, 설치, 자동 재기동, 클러스터 상태 확인 |
| 3 | 나머지 Koral 노드 | 앞선 노드가 정상화된 후 같은 절차를 노드별로 반복 |
| 4 | 공유FS VM | 의존 작업 중지, 사전 점검, 설치, 자동 재기동, 공유 경로 및 클라이언트 확인 |
| 5 | 전체 작업 대상 | 버전과 서비스 상태 최종 확인, 실행 로그 보관 |

실제 대상 순서는 클러스터 가용성과 스토리지 의존관계에 따라 작업 전에 확정합니다. 공유FS VM이 여러 대라면 각 VM과 연결된 클라이언트가 정상화된 뒤 다음 VM을 진행합니다.

## 4 대상 VM 재기동 및 완료 확인

적용 명령은 대상 VM을 자동 재기동하고, SSH 재접속 후 Boot ID 변경과 실행 커널을 확인합니다. CCVM 출력의 `Reboot confirmed:`, `Updated kernel version: 6.12.117+deb12-amd64`, `[8/8] SUCCESS: reboot and kernel checks passed.`를 확인합니다. 이 리비전에서는 서비스 상태 검사가 생략되므로 5절의 기능 점검까지 완료해야 합니다.

설치·재기동이 지연되거나 SSH 재접속에 실패하면 다음 대상의 작업을 멈춥니다. 콘솔에서 대상 VM 상태를 확인하고 기존 실행 결과를 점검한 후 재시도 여부를 결정합니다.

## 5 업데이트 완료 후 점검

| 구분 | 확인 항목 |
| --- | --- |
| 대상 VM 공통 | 새 커널로 부팅, 실행 커널 패키지·CA 인증서·OpenJDK 패키지 버전, 실패 서비스 |
| Koral | 노드 Ready, kubelet·컨테이너 런타임, Pod 및 애플리케이션 정상 동작 |
| Koral 컨트롤 노드 | Kubernetes API 및 컨트롤 플레인·etcd 가용성 |
| 공유FS | 스토리지 서비스, 공유 디스크·파일시스템 마운트 및 클라이언트 연결 |
| 공유FS 사용 애플리케이션 | 승인된 테스트 경로에서 읽기·쓰기 확인, 테스트 파일 정리, 작업 재개 후 동작 확인 |
| Java 사용 서비스 | 실제 런타임 경로, 실행 버전 및 서비스 정상 동작 |

**각 대상 VM에서 버전과 실패 서비스를 확인합니다.**

```bash
uname -r
dpkg-query -W "linux-image-$(uname -r)" ca-certificates openjdk-17-jre-headless
systemctl --failed --no-pager
```

Java를 사용하는 대상에서는 `java -version`과 서비스의 실제 실행 경로를 확인합니다. 출력된 패키지 버전은 1절의 배포 목표와 비교합니다.

**Koral 클러스터 관리 환경에서 노드와 Pod를 확인합니다.**

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

작업 전에 cordon한 노드는 정상화 확인 후 운영 절차에 따라 uncordon하고, 스케줄링과 워크로드 상태를 다시 확인합니다.

## 6 작업 기록 및 오류 확인

| 구분 | 확인 내용 |
| --- | --- |
| 정상 완료 기록 | 대상 IP·역할, 작업 전후 버전, 스크립트 출력의 `Run:`과 `Local logs:`, 서비스 점검 결과 |
| 체크섬 오류 | 원본 번들과 대응하는 체크섬 파일을 다시 확인 |
| SSH 또는 역할 식별 오류 | 실제 대상 IP·포트, 인증 정보 및 VM 역할 확인 |
| 설치·부팅·재접속 오류 | CCVM의 `controller.log`·`remote.log`, 대상 VM의 `run.log`·`verify.log` 및 콘솔 확인 |
| 기능 점검 실패 | 대상 서비스 및 클라이언트 로그를 확인하고 서비스 복구 후 후속 작업 재개 |

대상 VM의 실행 로그는 `/var/lib/systemvm-kernel-rollout/<Run ID>/`에서 확인합니다. 기존 실행의 재기동·커널 검증만 다시 수행할 때는 CCVM에서 아래 예시의 `<Run ID>`를 해당 대상의 실제 값으로 교체합니다.

```bash
cd /opt/rpm
bash deploy-systemvm-kernel.sh \
  -k /var/cloudstack/management/.ssh/id_rsa \
  -i 10.10.1.59 -p 2222 --verify-only '<Run ID>'

bash deploy-systemvm-kernel.sh -t sharedfs \
  -i 10.10.254.39 -p 22 --verify-only '<Run ID>'
```

## 7 작업 시 주요 주의사항

1. 작업 전 대상 VM의 콘솔 접근과 서비스 복구 수단을 확인합니다.
2. 한 번에 VM 한 대씩 적용하고, 이전 대상의 서비스 정상화를 확인한 후 다음 대상을 진행합니다.
3. 적용 명령 실행 전에 Koral 워크로드 이동 또는 공유FS 의존 작업 중지를 완료합니다.
4. 사전 점검, 설치, 재기동 또는 기능 점검 중 오류가 발생하면 후속 대상 작업을 중단합니다.
5. 최종 완료는 실행 커널, 패키지 버전, 역할별 기능을 모두 확인한 시점으로 기록합니다.

**최종 작업 흐름**

CCVM에 배포 파일 배치 → 체크섬 검증 → 대상별 사전 점검 → 순차 업데이트 → VM별 자동 재기동 → 커널·패키지·서비스 확인 → 작업 로그 보관
