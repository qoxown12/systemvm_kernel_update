# 최종 통합 묶음 안내

tar.gz 방식의 적용 파일:

```text
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz
debian12-kernel-amd64-20261106T074740Z-NJPHLu8I.tar.gz.sha256
```

적용 순서와 명령은 [INSTALL.md](INSTALL.md)를 따릅니다.

같은 구성의 ISO도 제공합니다. ISO 연결·마운트·실행과 tar.gz/ISO 재생성 방법은 [BUILD.md](BUILD.md)를 따릅니다.

**반입 → 체크섬 확인 → 압축 해제 → check → install → check-boot → 직접 재부팅 → verify → 서비스 확인**

실제 설치 파일은 `repo/`, 포함 패키지 목록은 `packages.tsv`, 대상 VM의 설치 로그는 `logs/`에 있습니다. 수정·검증 이력은 `plan.md`에 기록되어 있습니다.

## 원격 적용 로그 위치

원격 적용 로그는 명령을 실행한 VM의 다음 경로에 실행별로 저장됩니다.

```text
/var/lib/systemvm-kernel-rollout/systemvm-rollout-<UTC시간>-<대상IP>-port-<SSH포트>-<실행식별자>-<식별자>/
  controller.log  # 전체 진행 상황과 오류
  remote.log      # 종료 시 대상 VM에서 수집한 설치·GRUB·검증 로그
```

실행 계정에는 `/var/lib/systemvm-kernel-rollout/`의 쓰기 권한이 필요합니다. root로 실행하거나 해당 디렉터리의 쓰기 권한을 미리 준비합니다. 로그 생성에 실패하면 대상 VM 접속 전에 종료합니다.

대상 VM의 원본 로그는 `/var/lib/systemvm-kernel-rollout/<실행ID>/`에 남습니다. 종료 시 대상에 접속할 수 없으면 `remote.log` 수집에 실패할 수 있으며, `log-fetch-error.txt`에서 수집 오류를 확인합니다. 자세한 원격 실행 방법은 [REMOTE-INSTALL.md](REMOTE-INSTALL.md)를 참고합니다.
