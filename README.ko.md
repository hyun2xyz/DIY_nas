# DIY_nas

English documentation: [README.md](README.md)

DIY_nas는 기존 Windows PC를 그대로 유지하면서 Hyper-V Ubuntu VM 안에 NAS형 웹 드라이브를 구성하는 공개 템플릿입니다.

## 무엇을 만드는가

```text
Windows 호스트
  - SSD의 기존 Windows 설치는 유지
  - Hyper-V로 Ubuntu Server VM 실행
  - 선택한 HDD를 VM에 pass-through 연결

Ubuntu VM
  - ZFS mirror로 운영 드라이브 저장소 구성
  - Docker Engine 실행
  - FileBrowser Quantum으로 사람용 웹 드라이브 UI 제공
  - 선택적으로 Node Gateway API 실행

외부 공개 선택 사항
  - Cloudflare Tunnel로 필요한 로컬 서비스만 HTTPS로 공개
```

이 저장소는 홈랩, 소규모 내부 팀, NAS 학습/운영 실험을 위한 템플릿입니다. 완제품 NAS 어플라이언스가 아니므로 디스크 선택, 백업 정책, 외부 공개, 인증 설정은 각 환경에서 반드시 재검토해야 합니다.

## 포함 내용

- Windows + Hyper-V 기반 구성 문서
- Ubuntu Server + Docker 기반 NAS 서비스 구조
- 명시적 확인 플래그가 필요한 ZFS mirror 구성 스크립트
- FileBrowser Quantum Docker 구성
- 선택형 Node Gateway API 예제
- 선택형 Cloudflare Tunnel 헬퍼 스크립트
- 공개 전 민감정보 점검 도구
- 다른 에이전트가 이어받기 위한 [AGENT_GUIDE.md](AGENT_GUIDE.md)

## 빠른 시작

```powershell
git clone https://github.com/hyun2xyz/DIY_nas.git
cd DIY_nas
npm install
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

Windows PowerShell에서 `npm` 실행이 정책 때문에 막히면 `npm.cmd`를 사용하세요.

## 핵심 구조

```text
scripts/
  linux/       Ubuntu 내부 설정 스크립트
  vm/          Hyper-V 보조 스크립트
  gateway/     선택형 API Gateway 및 WebDAV 보조 스크립트
  cloudflare/  선택형 Cloudflare Tunnel 보조 스크립트
  audit/       공개 배포 점검

src/
  선택형 Gateway/API 레이어 예제

docs/
  아키텍처, 설치 출처, 안전 규칙, 공개 체크리스트
```

## 안전 규칙

- `/`, `/var`, Docker 볼륨 전체, 사용자 홈 전체를 웹 드라이브에 노출하지 않습니다.
- `/srv/nas/live/drive`처럼 의도한 NAS 데이터 경로만 마운트합니다.
- `.env`, 앱 비밀번호, 터널 토큰, 디스크 시리얼, 실제 도메인, 실제 IP, 백업 아카이브는 Git에 넣지 않습니다.
- 저장소를 지우는 스크립트는 디스크 식별값을 확인하고 명시적 확인 플래그를 사용한 뒤 실행합니다.
- HTTPS, 강한 비밀번호, 최소 권한 계정, 자동화 전용 계정을 사용합니다.

## 검증

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

`audit:public`은 공개 저장소에 들어가면 안 되는 대표적인 개인 환경 문자열을 검사합니다.

## 외부 소프트웨어

이 저장소는 외부 바이너리를 재배포하지 않습니다. Ubuntu apt, Docker 공식 저장소, FileBrowser Quantum 컨테이너 이미지, Cloudflare cloudflared 릴리스 채널 등 각 프로젝트의 공식 배포 경로에서 설치하는 구조입니다. 운영 전 각 프로젝트의 라이선스와 약관을 확인하세요.

## 라이선스

MIT License. 자세한 내용은 [LICENSE](LICENSE)를 확인하세요.
