# 에이전트 운영 가이드

이 파일은 다른 코딩 에이전트가 이 저장소를 이어받아 개발할 때 읽는 관리 문서입니다. 실제 운영 값은 포함하지 않습니다.

## 프로젝트 목적

OpenNAS Drive Pipeline은 Windows PC에서 Hyper-V Ubuntu VM을 실행하고, 대용량 HDD를 NAS 드라이브로 사용하는 공개 템플릿입니다. 사람은 FileBrowser Quantum 웹 UI로 파일을 관리하고, 외부 시스템은 선택형 Gateway API로 파일 저장소를 사용할 수 있습니다.

## 현재 기준 아키텍처

```text
Windows host
  ├─ Hyper-V Ubuntu VM
  ├─ cloudflared connector
  └─ optional local scripts

Ubuntu VM
  ├─ ZFS live mirror
  ├─ /srv/nas/live/drive
  ├─ Docker
  ├─ FileBrowser Quantum
  └─ optional Node Gateway

External clients
  ├─ Browser -> FileBrowser Quantum
  └─ Service integration -> Gateway API
```

## 중요한 결정

1. 사람용 웹 드라이브는 FileBrowser Quantum을 사용합니다.
2. API 연동은 Node Gateway를 선택적으로 유지합니다.
3. 운영 데이터는 ZFS mirror에 둡니다.
4. 백업은 mirror와 별도로 설계합니다.
5. 공개 HTTPS 연결은 Cloudflare Tunnel을 기본 문서화 대상으로 둡니다.
6. 공개 repo에는 실제 운영 값이 들어가지 않습니다.

## 에이전트 작업 원칙

- 먼저 `README.md`, `docs/public-pipeline-overview.ko.md`, `docs/glossary.ko.md`를 읽고 전체 구조를 파악합니다.
- 스크립트를 수정할 때는 파괴적 작업의 기본값이 안전한지 확인합니다.
- `.env.example`은 공개 가능해야 하고, `.env`는 절대 공개하지 않습니다.
- 설치 문서를 바꾸면 검증 명령도 함께 갱신합니다.
- 실제 도메인이나 IP가 필요하면 placeholder를 사용합니다.
- FileBrowser에 연결되는 경로는 NAS 전용 mountpoint로 제한합니다.

## 검증 명령

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

## 주요 파일 역할

- `README.md`: 공개 저장소 첫 화면
- `docs/public-pipeline-overview.ko.md`: 전체 파이프라인 설명
- `docs/glossary.ko.md`: 용어 설명
- `docs/installation-sources.ko.md`: 패키지 설치 소스
- `docs/2026-05-20-filebrowser-quantum-drive.md`: FileBrowser Quantum 드라이브 설계
- `scripts/linux/setup-filebrowser-quantum.sh`: Ubuntu VM 안에서 FileBrowser Quantum 구성
- `scripts/audit-public-release.ps1`: 공개 금지 값 검사
- `src/`: Gateway/API 예제
- `tests/`: Node 테스트

## 변경 후 기록할 것

변경이 끝나면 다음 정보를 PR 또는 커밋 메시지에 남깁니다.

- 무엇을 바꿨는지
- 왜 바꿨는지
- 어떤 검증을 실행했는지
- 운영자가 직접 해야 할 수동 작업이 있는지

## 금지 사항

- 실제 비밀번호나 token을 코드에 넣기
- 실제 운영 도메인을 문서에 넣기
- 실제 디스크 시리얼을 문서에 넣기
- 백업 파일을 Git에 추가하기
- FileBrowser source를 시스템 루트로 설정하기
- 디스크 초기화를 dry-run 없이 실행하게 만들기
