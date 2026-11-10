Debian 12 / bookworm / amd64 SystemVM 커널 오프라인 업데이트

인터넷 가능한 준비 VM에서 묶음을 다시 생성하려면:
  cd /root/rpm
  sudo bash prepare-debian12-kernel-offline.sh ./output

output 폴더는 자동 생성되며 새 아카이브, 체크섬 및 작업 파일이 저장됩니다.
출력 경로를 생략하면 /var/tmp/debian12-kernel-offline을 사용합니다.
재생성 시점의 저장소를 조회하므로 커널 버전과 파일명이 달라질 수 있습니다.

ISO가 필요하면 build-kernel-iso.sh와 run-kernel-from-iso.sh도 같은
디렉터리에 두고 genisoimage, python3를 준비한 뒤 실행합니다.
  bash build-kernel-iso.sh ./output/실제-생성한-묶음.tar.gz
tar.gz와 같은 구성의 .iso 및 .iso.sha256가 생성됩니다.
빌드 절차와 VM의 ISO 마운트·적용 명령은 BUILD.md를 따릅니다.
ISO 루트의 install-kernel.sh를 실행하면 쓰기 가능한 로컬 경로에
자동 준비하여 실행하므로 사용자가 직접 압축을 풀 필요가 없습니다.

준비 스크립트와 같은 디렉터리에 있어야 하는 보조 파일:
  kernel-offline-tools.py
  kernel-boot-check.sh
  install-kernel-offline.sh
  collect-systemvm-state.sh
  README-KO.txt

준비 프로젝트의 history와 tests 폴더는 실행 필수가 아닙니다.
output은 생성 결과이므로 필요한 아카이브와 체크섬을 보관한 뒤 정리합니다.
이 설명은 준비 프로젝트 기준입니다. 반입한 설치 묶음 안의 파일은
SHA256SUMS로 검사하므로 임의로 일부를 삭제하지 않습니다.

배포받은 .tar.gz와 같은 이름의 .tar.gz.sha256 파일을 함께 반입합니다.
커널·의존성 .deb, 설치기 및 부팅 검사기가 포함되어 있습니다.
포함 패키지 이름·버전은 packages.tsv와 BUILD-INFO.txt에서 확인합니다.

root에서 아카이브 체크섬을 확인하고 압축을 푼 뒤:
  bash install-kernel.sh check

점검 통과 후 설치:
  bash install-kernel.sh install

부팅 항목 검사:
  bash install-kernel.sh check-boot

기존 /boot/grub/grub.cfg를 우선 사용하여 GRUB2 설정을 갱신·검사합니다.
후보 파일의 메뉴·문법·기본 부팅 항목 검증 후 반영하며 백업 경로를
출력합니다. 저장된 부팅 항목 등 별도 검토가 필요한 설정은 중단합니다.

현재 부팅 처리 리비전은 BOOT-CONFIG-REVISION.txt 첫 줄에서 확인합니다.

부팅 선택과 복구 방법을 확인하고 점검 시간에 직접 재부팅합니다.
재접속한 뒤:
  bash install-kernel.sh verify
  uname -r
  systemctl --failed

설치기는 자동 재부팅이나 기존 커널 제거를 수행하지 않습니다.
목표 커널 설치가 완료된 VM은 check-boot로 확인하고, 필요한 재부팅 후
verify와 서비스 기능 검증을 진행하면 됩니다.

파일 위치:
  repo/          실제 .deb 파일과 로컬 APT 인덱스
  packages.tsv   포함된 전체 패키지 이름·버전 목록
  logs/          대상 VM의 점검·설치 실행 로그
  source/        다운로드 준비 스크립트와 보조 파일
  plan.md        변경 내용과 작업·검증 이력

여러 구버전 VM의 패키지 구성이 다르면 각각 check를 수행합니다.
추가 의존성이 필요하면 collect-systemvm-state.sh로 상태를 수집하고
prepare-debian12-kernel-offline.sh의 --target-status 옵션으로 반영합니다.
인터넷 가능한 준비 환경에서 실행하는 예:
  bash prepare-debian12-kernel-offline.sh ./output --target-status ./vm-a/status
여러 상태를 반영할 때는 --target-status 옵션을 반복합니다.

재생성되는 SystemVM에도 유지하려면 호환되는 템플릿을 별도로 갱신하고
검증해야 합니다. 같은 ABI 패키지 갱신 시 이전 빌드 파일은 교체될 수
있으므로 복구 가능한 백업과 콘솔을 준비합니다.
