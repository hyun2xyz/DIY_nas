# 오픈소스 릴리스 계획

## 목적

이 저장소는 개인 운영 환경에서 검증한 NAS 드라이브 파이프라인을 공개 가능한 템플릿으로 정리합니다. 목표는 다른 사용자가 Windows PC와 대용량 HDD를 이용해 비슷한 셀프호스팅 파일 서버를 구성할 수 있게 하는 것입니다.

## 대상 사용자

- Windows PC를 계속 사용하면서 NAS 기능을 추가하려는 사용자
- Hyper-V Ubuntu VM으로 Linux 서버를 운영하려는 사용자
- 대용량 HDD를 mirror 구조로 묶어 파일 저장소를 만들려는 사용자
- Nextcloud보다 가벼운 웹 파일 관리자 UI를 원하는 사용자
- 위키, LMS, 글쓰기 사이트 같은 외부 서비스와 파일 저장소를 연결하려는 사용자

## 공개 범위

포함합니다.

- 공개용 설치 문서
- 공개용 Docker/Compose 템플릿
- 공개용 PowerShell/Bash 스크립트
- FileBrowser Quantum 구성 예시
- Gateway API 샘플
- 테스트 코드
- 공개 전 감사 스크립트
- 에이전트 작업 지침

포함하지 않습니다.

- 실제 도메인
- 실제 이메일
- 실제 계정명
- 실제 내부 IP
- 실제 디스크 시리얼
- 실제 API token
- 실제 app password
- 운영 백업 파일
- 개인 사이트 전용 비공개 코드

## 저장소 구조

```text
.
├─ README.md
├─ AGENTS.md
├─ agent.md
├─ docs/
├─ scripts/
│  ├─ linux/
│  ├─ backup/
│  ├─ health/
│  └─ vm/
├─ src/
├─ public/
├─ samples/
├─ tests/
└─ tools/
```

## 릴리스 전 체크리스트

1. 공개 문서가 실제 운영 값을 포함하지 않는지 확인합니다.
2. `.env.example`만 공개하고 `.env`는 제외합니다.
3. `npm.cmd run check`를 실행합니다.
4. `npm.cmd test`를 실행합니다.
5. `npm.cmd run audit:public`을 실행합니다.
6. 공개 대상 폴더에 파일을 복사합니다.
7. 새 Git 저장소에서 커밋합니다.
8. GitHub 원격 저장소로 push합니다.

## 유지보수 원칙

- 실제 운영 값은 항상 placeholder로 바꿉니다.
- 디스크를 지우는 명령은 기본값으로 실행되지 않게 합니다.
- 설치 문서는 “원리”, “절차”, “검증”, “복구”를 분리해서 작성합니다.
- 자동화 스크립트는 dry-run 또는 명시적 확인 플래그를 둡니다.
- 에이전트가 이어받을 수 있도록 변경 이유와 검증 결과를 문서에 남깁니다.
