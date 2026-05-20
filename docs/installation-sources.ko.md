# 설치 소스 정리

이 문서는 OpenNAS Drive Pipeline을 구성할 때 필요한 주요 패키지를 어디서 받을 수 있는지 정리합니다.

## Windows host

### Git

GitHub 저장소를 clone하고 스크립트를 관리하는 데 필요합니다.

```powershell
winget search Git
winget install --id Git.Git -e
```

공식 설치 파일을 사용해도 됩니다.

### Node.js LTS

Gateway API 예제와 검증 스크립트 실행에 필요합니다.

```powershell
winget search Node.js
winget install --id OpenJS.NodeJS.LTS -e
```

설치 후 확인:

```powershell
node --version
npm.cmd --version
```

### Hyper-V

Ubuntu VM을 실행하는 데 필요합니다. Windows 기능에서 Hyper-V를 켜거나 PowerShell로 활성화합니다.

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

활성화 후 재부팅이 필요할 수 있습니다.

### OpenSSH Client

Windows PowerShell에서 Ubuntu VM으로 접속할 때 사용합니다.

```powershell
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
```

설치가 필요하면 Windows 선택적 기능에서 OpenSSH Client를 추가합니다.

### Tailscale

선택 사항입니다. 같은 사설 네트워크처럼 Mac, Windows, 서버를 연결하고 싶을 때 사용합니다.

```powershell
winget search Tailscale
winget install --id Tailscale.Tailscale -e
```

### cloudflared

선택 사항입니다. Cloudflare Tunnel로 로컬 서비스를 공개 HTTPS 주소에 연결할 때 사용합니다.

```powershell
winget search cloudflared
```

Cloudflare Zero Trust 화면에서 제공하는 설치 명령을 그대로 사용하는 방식도 가능합니다.

## Ubuntu VM

### 기본 패키지

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
```

### ZFS

```bash
sudo apt install -y zfsutils-linux
zpool version
```

### Docker Engine

Docker 공식 apt 저장소를 추가한 뒤 설치합니다. 운영 환경에서는 Docker 공식 문서를 기준으로 설치 절차를 확인하세요.

설치 후 확인:

```bash
docker --version
docker compose version
sudo docker run --rm hello-world
```

### FileBrowser Quantum

Docker 이미지로 실행합니다.

```bash
docker pull gtstef/filebrowser:stable
```

이 저장소의 예시 스크립트:

```bash
sudo bash scripts/linux/setup-filebrowser-quantum.sh
```

기본적으로 FileBrowser에는 NAS 드라이브 전용 mountpoint만 연결해야 합니다.

## 공개 HTTPS

외부 브라우저에서 접근하려면 Cloudflare Tunnel, reverse proxy, Tailscale Funnel 같은 방법을 사용할 수 있습니다. 이 템플릿은 Cloudflare Tunnel을 기본 공개 방식으로 설명합니다.

## 주의

- 설치 명령은 배포판과 Windows 버전에 따라 달라질 수 있습니다.
- 실제 운영 전에는 각 패키지의 공식 문서를 확인하세요.
- 공개 주소를 열기 전에는 인증, 권한, 백업 정책을 먼저 정리하세요.
