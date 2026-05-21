```text
 ____ ___ __   __       _   _    _    ____
|  _ \_ _|\ \ / /      | \ | |  / \  / ___|
| | | | |  \ V / _____ |  \| | / _ \ \___ \
| |_| | |   | ||_____|| |\  |/ ___ \ ___) |
|____/___|  |_|       |_| \_/_/   \_\____/
```

<p align="center">
  <img src="public/diy-nas-line-art.svg" alt="DIY_nas 라인 아트: 노트북과 홈 서버가 연결된 그림" width="780">
</p>

English documentation: [README.md](README.md)

DIY_nas는 Windows를 지우지 않고 그대로 유지한 상태에서, Windows PC 안에 Linux 기반 NAS 스타일 웹 드라이브를 구성하는 공개용 템플릿입니다. 개인 환경 정보, 실제 도메인, 실제 IP, 비밀번호, 토큰, 디스크 시리얼은 포함하지 않습니다.

## 준비물!

설치 전에 아래 항목을 먼저 확인하세요. 에이전트가 이어서 개발하거나 운영할 때 필요한 세부 규칙은 [AGENT_GUIDE.md](AGENT_GUIDE.md)에 정리되어 있으므로, 이 README에는 기본 준비 항목만 둡니다.

```text
필요한 계정
- GitHub 계정: 이 템플릿을 포크하거나 공개 저장소로 운영할 때 필요
- 선택 Cloudflare 계정과 도메인: 외부 HTTPS 주소로 드라이브를 열 때 필요
- 선택 Tailscale 계정: 본인 기기끼리 사설망처럼 접속할 때 필요

필요한 Windows 호스트
- Windows 10/11 Pro, Enterprise, Education 권장: Hyper-V 사용을 전제로 함
- 관리자 권한 PowerShell과 Hyper-V 관리자
- BIOS/UEFI에서 가상화 기능 활성화
- 안정적인 NAS 접속을 위해 유선 LAN 권장

권장 호스트 사양
- CPU: 최소 4코어, 권장 8코어 이상
- 메모리: 파일럿 최소 16GB, 여유 있게 운영하려면 32GB 이상 권장
- SSD 여유 공간: Ubuntu VM 가상 디스크, 로그, 도구용으로 128GB 이상 권장
- Windows는 SSD에 그대로 유지하고, NAS OS를 Windows 위에 덮어 설치하지 않음

필요한 저장장치
- Windows 호스트 OS와 Ubuntu VM 가상 디스크용 SSD
- 운영용 미러 NAS 풀을 만들려면 최소 HDD 2개
- 운영 미러 + 백업 미러 구조를 만들려면 HDD 4개 권장
- 운영 데이터에는 NAS용 HDD 권장
- 각 디스크가 독립적으로 보이는 USB/SATA 도킹스테이션, HBA, 외장 인클로저
- 실제 데이터를 오래 운영한다면 UPS 권장

필요한 소프트웨어
- Git for Windows
- Node.js LTS와 npm
- Ubuntu Server LTS ISO
- Hyper-V
- Ubuntu 내부 Docker Engine과 Docker Compose plugin
- Ubuntu 내부 ZFS utilities
- FileBrowser Quantum Docker 이미지
- 선택 Cloudflare Tunnel용 cloudflared
```

## 무엇을 만드는가

```text
Windows 호스트
  - 기존 Windows 설치는 SSD에 그대로 유지
  - Hyper-V로 Ubuntu Server VM 실행
  - 선택한 HDD를 VM에 pass-through로 연결

Ubuntu VM
  - 운영 드라이브 저장소는 ZFS mirror 사용
  - Docker Engine 실행
  - 사람이 쓰는 웹 드라이브 UI는 FileBrowser Quantum 사용
  - 서비스 연동이 필요하면 선택적으로 Node Gateway 실행

선택 공개 접속
  - Cloudflare Tunnel로 필요한 로컬 서비스만 HTTPS 주소로 공개
```

이 프로젝트는 홈랩, 소규모 내부 팀, 학습용 NAS 구축을 위한 템플릿입니다. 완성형 NAS 제품처럼 모든 판단이 자동화된 어플라이언스는 아닙니다. 디스크 선택, 백업 정책, 외부 공개, 인증 방식은 각 머신과 운영 목적에 맞게 검토해야 합니다.

## 포함된 내용

- Windows와 Hyper-V 중심의 구성 메모
- Ubuntu Server와 Docker 기반 NAS 서비스 레이아웃
- 명시적 파괴 확인 플래그를 요구하는 ZFS mirror 구성 스크립트
- FileBrowser Quantum Docker 구성
- 선택 Node Gateway API 예시
- 선택 Cloudflare Tunnel 보조 스크립트
- 공개 배포 전 민감정보를 찾는 audit 도구
- 다른 에이전트에게 넘기기 위한 [AGENT_GUIDE.md](AGENT_GUIDE.md)

## 빠른 시작

```powershell
git clone https://github.com/hyun2xyz/DIY_nas.git
cd DIY_nas
npm install
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

Windows PowerShell에서 일반 `npm` 명령이 실행 정책 때문에 막히면 `npm.cmd`를 사용하세요.

## 핵심 구조

```text
scripts/
  linux/       Ubuntu 쪽 setup 스크립트
  vm/          Hyper-V 보조 스크립트
  gateway/     선택 API gateway와 WebDAV 보조 스크립트
  cloudflare/  선택 tunnel 보조 스크립트
  audit/       공개 배포 검사용 스크립트

src/
  선택 gateway/API 레이어를 위한 최소 Node 예시

docs/
  아키텍처, 설치 출처, 안전 규칙, 릴리스 체크리스트
```

## 안전 규칙

- `/`, `/var`, Docker volume, 전체 home 디렉터리를 웹 드라이브에 노출하지 마세요.
- `/srv/nas/live/drive`처럼 의도한 NAS 데이터 디렉터리만 마운트하세요.
- `.env`, 앱 비밀번호, 터널 토큰, 디스크 시리얼, 실제 도메인, 실제 IP, 백업 아카이브를 Git에 넣지 마세요.
- 디스크를 지우는 스크립트는 디스크 식별을 확인하고 명시적 확인 플래그를 사용한 뒤 실행하세요.
- HTTPS, 강한 비밀번호, 최소 권한 계정, 자동화용 분리 계정을 사용하세요.

## 검증

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

`audit:public`은 공개 전 저장소에 흔한 개인 환경 정보가 들어갔는지 검사합니다.

## 타사 소프트웨어

이 저장소는 타사 바이너리를 재배포하지 않습니다. 운영자는 Ubuntu apt 저장소, Docker 공식 저장소, FileBrowser Quantum 컨테이너 이미지, Cloudflare cloudflared 배포 채널 등 공식 배포 경로에서 필요한 소프트웨어를 설치합니다. 운영 환경에 쓰기 전 각 프로젝트의 라이선스와 약관을 확인하세요.

## 라이선스

MIT License. [LICENSE](LICENSE)를 확인하세요.
