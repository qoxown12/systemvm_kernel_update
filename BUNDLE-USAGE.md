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
