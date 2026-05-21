# 공개용 NAS 파이프라인 개요

이 문서는 Windows PC를 그대로 사용하면서, Hyper-V Ubuntu VM 안에 개인/소규모 팀용 NAS 드라이브를 구성하는 공개 템플릿을 설명합니다. 실제 운영 환경의 도메인, 계정, 토큰, 디스크 시리얼, 내부 IP는 포함하지 않습니다.

## 목표

- Windows 운영체제는 SSD에서 계속 사용합니다.
- Ubuntu Server는 Hyper-V VM으로 실행합니다.
- 대용량 HDD는 운영 데이터 미러와 백업 미러로 분리합니다.
- 사람은 웹 브라우저에서 FileBrowser Quantum으로 파일을 관리합니다.
- 외부 서비스는 필요할 때 Gateway API를 통해 파일을 업로드/다운로드합니다.
- 외부 공개 주소는 Cloudflare Tunnel로 연결합니다.

## 권장 구조

```text
Windows host
  ├─ SSD
  │   ├─ Windows
  │   └─ Hyper-V VM disk
  ├─ HDD 1 + HDD 2
  │   └─ Ubuntu VM pass-through, ZFS live mirror
  └─ HDD 3 + HDD 4
      └─ backup mirror 또는 별도 백업 볼륨

Ubuntu VM
  ├─ /srv/nas/live/drive
  │   ├─ files
  │   ├─ integrations
  │   ├─ shared
  │   └─ uploads
  ├─ Docker
  ├─ FileBrowser Quantum
  └─ Optional Node Gateway
```

## 왜 Ubuntu VM인가

Windows를 메인 작업 환경으로 유지하면서도 Linux 서버 도구를 안정적으로 사용할 수 있습니다. ZFS, Docker, 서버용 자동화 도구는 Ubuntu 환경에서 운영하기 쉽습니다. VM 파일은 SSD에 두고, 큰 데이터만 HDD에 둡니다.

## 왜 ZFS mirror인가

운영 데이터용 HDD 2개를 mirror로 묶으면 한 디스크가 고장나도 서비스가 계속 동작할 수 있습니다. 단, mirror는 백업이 아닙니다. 실수로 삭제한 파일이나 랜섬웨어 피해는 mirror에 즉시 반영될 수 있으므로 별도 백업이 필요합니다.

## 사용자용 웹 드라이브

사용자가 직접 파일을 보고, 올리고, 내려받는 UI는 FileBrowser Quantum이 담당합니다.

```text
Browser
  -> Cloudflare Tunnel 또는 사설 네트워크
  -> FileBrowser Quantum
  -> /srv/nas/live/drive
```

FileBrowser에는 전체 시스템 경로가 아니라 드라이브 전용 mountpoint만 연결합니다. 이 원칙이 중요합니다.

## API 연동 계층

위키, LMS, 글쓰기 사이트 같은 외부 시스템이 파일 저장소를 사용해야 하면 Node Gateway 같은 얇은 API 계층을 둘 수 있습니다.

```text
External site
  -> Gateway API
  -> storage backend
```

초기에는 Gateway를 유지하고, 운영이 안정되면 FileBrowser API 또는 WebDAV 기반 구조로 단순화할 수 있습니다.

## 공개 HTTPS 연결

로컬 PC에 공인 IP가 없거나 공유기 포트포워딩을 피하고 싶다면 Cloudflare Tunnel을 사용합니다.

```text
https://drive.example.com
  -> Cloudflare edge
  -> cloudflared connector on Windows host
  -> Ubuntu VM service port
```

Tunnel은 외부에서 집 PC로 직접 들어오는 포트를 열지 않고, Windows 쪽 connector가 Cloudflare로 outbound 연결을 유지하는 방식입니다.

## 운영 체크리스트

- VM 자동 시작 설정
- Docker 서비스 자동 시작
- FileBrowser 컨테이너 `restart: unless-stopped`
- Cloudflare Tunnel connector 서비스 등록
- 백업 볼륨 상태 확인
- 정기 백업 및 복구 테스트
- 공개 주소 인증/비밀번호 점검
- 공개 repo에는 실제 값이 들어가지 않았는지 감사 실행

## 공개 템플릿에서 빠진 것

- 실제 계정명
- 실제 도메인
- 실제 IP
- 실제 디스크 시리얼
- 실제 API 토큰
- 실제 앱 비밀번호
- 운영 백업 파일
- 개인 사이트 전용 코드
