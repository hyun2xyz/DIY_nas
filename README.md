# OpenNAS Drive Pipeline

Windows PC에서 운영체제는 그대로 유지하고, Hyper-V Ubuntu VM 안에 NAS용 파일 서버를 구성하는 공개 템플릿입니다. 목표는 4개의 대용량 HDD를 데이터 미러와 백업 미러로 나누고, Docker 기반 웹 드라이브와 API 연동 계층을 함께 운영하는 것입니다.

이 저장소는 실제 운영 환경에서 사용한 값이 아니라, 오픈소스로 공개 가능한 형태로 정리한 설치 문서, 스크립트, 샘플 코드, 검증 도구만 포함합니다.

## 구성 개요

```text
Windows host
  - SSD: Windows와 Hyper-V VM 파일 보관
  - HDD 1, 2: Ubuntu VM에 pass-through로 연결, 운영 데이터 미러
  - HDD 3, 4: Windows 또는 별도 백업 영역으로 사용, 백업 미러

Hyper-V Ubuntu VM
  - ZFS live mirror: 운영 파일 저장소
  - Docker Engine
  - FileBrowser Quantum: 사용자용 웹 드라이브 UI
  - Optional Node Gateway: 외부 서비스/API 연동

Cloudflare Tunnel
  - 공개 HTTPS 주소를 로컬 서비스로 안전하게 연결
```

## 무엇을 포함하나

- Windows + Hyper-V + Ubuntu VM 기반 NAS 파일 서버 설계
- ZFS mirror 기반 운영 데이터 저장소 템플릿
- FileBrowser Quantum Docker 구성 스크립트
- 선택형 Node Gateway API 예제
- Cloudflare Tunnel 연결 가이드
- 공개 전 개인정보/토큰/도메인 누락 여부를 검사하는 감사 스크립트
- 다른 에이전트가 이어받아 관리할 수 있는 `AGENTS.md`, `agent.md`

## 빠른 시작

```powershell
git clone https://github.com/hyun2xyz/opennas.git
cd opennas
npm install
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

PowerShell에서 `npm` 실행이 정책에 막히면 `npm.cmd`를 사용하세요.

## 주요 설치 소스

Windows 쪽은 보통 다음 경로를 사용합니다.

- Git: Git for Windows 또는 `winget`
- Node.js LTS: Node.js 공식 설치 파일 또는 `winget`
- Hyper-V: Windows 기능 켜기/끄기
- OpenSSH Client: Windows 선택적 기능
- Tailscale: 선택 사항, 사설 장치 간 접속용
- cloudflared: 선택 사항, Cloudflare Tunnel 연결용

Ubuntu VM 안에서는 보통 다음 패키지를 사용합니다.

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release zfsutils-linux
```

Docker Engine은 Docker 공식 apt 저장소를 추가해서 설치합니다. FileBrowser Quantum은 Docker 이미지 `gtstef/filebrowser:stable`을 사용합니다.

자세한 설치 소스는 [docs/installation-sources.ko.md](docs/installation-sources.ko.md)를 보세요.

## 설치 흐름

1. Windows에서 Hyper-V를 켭니다.
2. SSD에 Ubuntu Server VM을 생성합니다.
3. 운영 데이터용 HDD 2개를 VM에 pass-through로 연결합니다.
4. Ubuntu 안에서 ZFS mirror를 구성합니다.
5. `/srv/nas/live/drive` 같은 안전한 mountpoint만 웹 드라이브에 노출합니다.
6. FileBrowser Quantum을 Docker로 실행합니다.
7. 필요하면 Node Gateway를 별도 포트로 실행합니다.
8. 외부 공개가 필요하면 Cloudflare Tunnel을 붙입니다.

## 보안 원칙

- `/`, `/var`, Docker 전체 볼륨, 사용자 홈 전체를 웹 드라이브에 노출하지 않습니다.
- 공개 주소를 열 때는 HTTPS와 강한 비밀번호를 사용합니다.
- API 업로드는 토큰 인증을 요구합니다.
- `.env`, 토큰, 앱 비밀번호, 실제 도메인, 실제 IP, 디스크 시리얼은 커밋하지 않습니다.
- 디스크 초기화 스크립트는 반드시 대상 디스크를 확인한 뒤 실행합니다.

## 문서

- [전체 공개 파이프라인 개요](docs/public-pipeline-overview.ko.md)
- [용어 정리](docs/glossary.ko.md)
- [설치 소스 정리](docs/installation-sources.ko.md)
- [FileBrowser Quantum 드라이브 설계](docs/2026-05-20-filebrowser-quantum-drive.md)
- [공개 전 정리 체크리스트](docs/publication-sanitization-checklist.md)
- [오픈소스 릴리스 계획](docs/open-source-release-plan.md)

## 개발 검증

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

`audit:public`은 공개 저장소에 들어가면 안 되는 값이 포함되어 있는지 검사합니다.

## 라이선스

MIT License. 자세한 내용은 [LICENSE](LICENSE)를 확인하세요.
