# 오픈소스 NAS 클라우드 구축 파이프라인 정리

이 문서는 Windows PC와 8TB급 HDD 여러 개를 이용해 개인/팀용 NAS 클라우드 서버를 구축하는 오픈소스 프로젝트의 전체 방향을 설명합니다.

목적은 특정 개인 환경을 그대로 공개하는 것이 아니라, 검증한 구축 과정을 누구나 재현할 수 있는 공개 템플릿으로 정리하는 것입니다. 실제 계정, 도메인, IP, 디스크 시리얼, API 토큰, 앱 비밀번호는 모두 placeholder로 다룹니다.

## 1. 한 줄 요약

Windows는 그대로 SSD에서 사용하고, Hyper-V 안에 Ubuntu Server VM을 올린 뒤, 8TB HDD 4개를 운영용 미러와 백업용 미러로 나누어 파일 서버를 구성합니다. 사람용 웹 드라이브는 FileBrowser Quantum으로 제공하고, 외부 서비스 연동은 별도 Gateway API로 처리합니다. 외부 접속은 Cloudflare Tunnel을 통해 HTTPS 주소로 엽니다.

## 2. 기준 하드웨어 구성

예시 기준입니다. 실제 공개 저장소에서는 사용자 환경에 맞게 값만 바꾸면 됩니다.

```text
Windows Host PC
├─ SSD
│  ├─ Windows OS
│  └─ Hyper-V Ubuntu VM 가상 디스크
├─ HDD 1: 8TB NAS용 HDD
├─ HDD 2: 8TB NAS용 HDD
├─ HDD 3: 8TB 일반/백업용 HDD
└─ HDD 4: 8TB 일반/백업용 HDD
```

중요한 원칙:

- SSD는 Windows와 Ubuntu VM 실행용입니다.
- SSD는 절대 포맷 대상이 아닙니다.
- HDD 1, 2는 운영용 저장소로 묶습니다.
- HDD 3, 4는 백업용 저장소로 둡니다.
- RAID 또는 미러는 서비스 지속성을 높이는 장치이고, 백업을 대체하지 않습니다.

## 3. 저장소 설계

권장 구조는 다음과 같습니다.

```text
운영용 저장소
HDD 1 + HDD 2
→ ZFS mirror
→ livepool
→ /srv/nas/live/drive

백업용 저장소
HDD 3 + HDD 4
→ Windows Storage Spaces mirror 또는 별도 백업 미러
→ 백업 아카이브 저장
```

### 운영용 미러

운영용 미러는 실제 파일 서비스가 사용하는 저장소입니다.

예시:

```text
HDD 1 8TB + HDD 2 8TB
→ mirror
→ 사용 가능 용량 약 8TB
→ HDD 1개가 고장나도 서비스는 계속 가능
```

장점:

- 한 디스크가 고장나도 데이터 접근 가능
- 복구 시 새 디스크를 붙여 리빌드 가능
- 파일 서버 운영에 적합

주의:

- 실수로 파일을 지우면 미러 양쪽에서 같이 지워집니다.
- 랜섬웨어, 잘못된 명령, 앱 버그에는 별도 백업이 필요합니다.

### 백업용 미러

백업용 미러는 운영용 저장소의 백업을 보관하는 저장소입니다.

예시:

```text
HDD 3 8TB + HDD 4 8TB
→ mirror
→ 사용 가능 용량 약 8TB
→ 운영용 저장소 장애나 실수 복구에 사용
```

백업용 저장소는 평소에는 서비스 트래픽을 직접 받지 않고, 예약 백업이나 수동 백업 결과를 보관합니다.

## 4. OS와 가상화 구조

전체 구조는 Windows를 유지한 채, 그 안에서 Linux 서버를 운영하는 방식입니다.

```text
Windows Host
├─ Hyper-V
│  └─ Ubuntu Server VM
│     ├─ Docker Engine
│     ├─ ZFS
│     ├─ FileBrowser Quantum
│     └─ Node Gateway API
└─ Cloudflare Tunnel Connector
```

### Windows를 유지하는 이유

- 기존 Windows 작업 환경을 그대로 사용할 수 있습니다.
- Blender, 편집툴, 브라우저, 개발 도구를 그대로 유지할 수 있습니다.
- NAS 서버는 Hyper-V 안의 Ubuntu VM으로 분리됩니다.

### Ubuntu Server를 쓰는 이유

- Docker 운영이 안정적입니다.
- ZFS, 백업, 서비스 자동화 구성이 쉽습니다.
- 서버 운영 자료와 예제가 많습니다.
- Windows 본체를 직접 NAS OS로 바꾸지 않아도 됩니다.

## 5. 주요 서비스 역할

### FileBrowser Quantum

사람이 브라우저로 직접 쓰는 웹 드라이브입니다.

역할:

- 파일 탐색
- 업로드/다운로드
- 폴더 생성
- 파일 이동/삭제
- 사용자/그룹별 권한 관리
- 공유 링크
- WebDAV 접근

권장 공개 주소:

```text
https://drive.example.com
```

내부 서비스 예시:

```text
http://<VM_IP>:8090
```

컨테이너는 NAS 저장소 전체가 아니라, 안전하게 제한된 폴더만 봐야 합니다.

```text
호스트 경로: /srv/nas/live/drive
컨테이너 경로: /srv
```

절대 노출하지 말아야 할 예:

```text
/
/var
/home 전체
/etc
Docker volume 전체
Nextcloud 데이터 전체
```

### Node Gateway API

외부 사이트나 자동화 코드가 파일을 업로드/다운로드하기 위한 API 서버입니다.

역할:

- Wiki 첨부파일 업로드
- LMS 파일 업로드
- 글쓰기 사이트 첨부파일 업로드
- 다운로드 URL 생성
- 토큰 기반 API 인증

예시 엔드포인트:

```text
GET  /health
POST /files/upload
GET  /files/download?root=Wiki&path=<path>
```

Gateway는 사람이 쓰는 드라이브 UI가 아니라, 다른 시스템이 호출하는 통합 API입니다.

### Nextcloud

초기 파일 클라우드 검증에 사용한 선택지입니다.

현재 최종 방향에서는 다음처럼 정리합니다.

```text
사람용 웹 드라이브
→ FileBrowser Quantum

외부 시스템/API 연동
→ Node Gateway API

Nextcloud
→ 선택/레거시/비교용 구성
```

Nextcloud는 캘린더, 연락처, 협업 앱 생태계가 필요할 때는 유리하지만, 단순하고 빠른 NAS 파일 관리 목적에는 FileBrowser Quantum이 더 가볍습니다.

### Cloudflare Tunnel

로컬 PC나 VM의 서비스를 외부 HTTPS 주소로 열어주는 터널입니다.

포트포워딩 없이 다음과 같은 연결을 만들 수 있습니다.

```text
외부 브라우저
→ https://drive.example.com
→ Cloudflare Tunnel
→ Windows/NAS 또는 Ubuntu VM 내부 서비스
→ FileBrowser Quantum
```

장점:

- 집 공유기 포트포워딩이 필요 없습니다.
- 공인 IP가 없어도 됩니다.
- HTTPS를 쉽게 붙일 수 있습니다.
- 서비스별 공개 도메인을 나눌 수 있습니다.

예시:

```text
drive.example.com  → http://<VM_IP>:8090
api.example.com    → http://localhost:8791
```

## 6. 전체 파이프라인

```text
사용자 브라우저
  ↓
https://drive.example.com
  ↓
Cloudflare Tunnel
  ↓
Windows Host
  ↓
Hyper-V Ubuntu VM
  ↓
FileBrowser Quantum
  ↓
/srv/nas/live/drive
  ↓
ZFS live mirror
  ↓
HDD 1 + HDD 2
```

외부 서비스 연동은 다음 흐름입니다.

```text
위키 / LMS / 글쓰기 사이트
  ↓
Gateway API
  ↓
인증 토큰 검사
  ↓
파일 저장 경로 결정
  ↓
NAS 저장소 또는 WebDAV backend
  ↓
다운로드 URL 반환
```

## 7. 설치 순서

### 1단계: 저장소 클론

```powershell
git clone https://github.com/<OWNER>/<REPO>.git
cd <REPO>
```

Node.js 기반 Gateway와 검증 스크립트를 쓰려면 Node 20 이상을 권장합니다.

```powershell
npm install
npm run check
npm test
```

### 2단계: Hyper-V 활성화

Windows에서 Hyper-V 기능을 켭니다.

예시 스크립트:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\vm\enable-hyperv.ps1
```

재부팅이 필요할 수 있습니다.

### 3단계: Ubuntu Server VM 생성

Ubuntu Server ISO를 준비하고, Hyper-V VM을 생성합니다.

원칙:

- VM 가상 디스크는 SSD에 둡니다.
- 운영 데이터는 나중에 HDD/ZFS 저장소에 둡니다.
- VM 이름은 예시로 `nas-linux-pilot` 같은 값을 사용할 수 있습니다.

### 4단계: Ubuntu Server 설치

Ubuntu Server 설치 시 권장:

- OpenSSH Server 설치
- 일반 사용자 계정 생성
- Docker와 ZFS는 설치 후 별도 구성
- 설치 디스크는 VM의 128GB급 가상 디스크 사용

### 5단계: Docker 설치

Ubuntu 안에서 Docker를 설치합니다.

검증:

```bash
docker version
docker compose version
sudo docker run hello-world
```

### 6단계: ZFS 설치

```bash
sudo apt update
sudo apt install -y zfsutils-linux
```

검증:

```bash
zpool version
zfs version
```

### 7단계: HDD 확인

디스크 작업 전에는 반드시 OS 디스크와 데이터 디스크를 구분합니다.

```bash
lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINTS
```

확인해야 할 것:

- SSD/VM 루트 디스크가 무엇인지
- HDD 1, 2가 운영용인지
- HDD 3, 4가 백업용인지
- 디스크 시리얼 또는 모델이 예상과 맞는지

### 8단계: 운영용 ZFS mirror 생성

운영용 HDD 2개를 ZFS mirror로 묶습니다.

예시 구조:

```text
livepool
└─ /srv/nas/live/drive
```

실제 스크립트는 반드시 dry-run 또는 명시적 파괴 플래그를 사용해야 합니다.

원칙:

- 대상 디스크를 먼저 출력합니다.
- 사용자가 확인한 뒤에만 실행합니다.
- SSD나 VM 가상 디스크는 대상에서 제외합니다.

### 9단계: FileBrowser Quantum 설치

예시:

```bash
sudo bash ~/setup-filebrowser-quantum.sh
```

검증:

```bash
cd ~/nas-cloud/filebrowser
sudo docker compose ps
sudo docker logs --tail=100 nas-filebrowser-quantum
curl http://127.0.0.1:8090/api/health
```

FileBrowser는 다음 경로만 노출합니다.

```text
/srv/nas/live/drive
```

추천 하위 폴더:

```text
/srv/nas/live/drive/files
/srv/nas/live/drive/integrations
/srv/nas/live/drive/shared
/srv/nas/live/drive/uploads
```

### 10단계: Cloudflare Tunnel 연결

Cloudflare Zero Trust에서 Tunnel을 만들고, Windows 또는 NAS 호스트에 `cloudflared`를 서비스로 등록합니다.

권장 라우팅:

```text
drive.example.com
→ HTTP
→ http://<VM_IP>:8090
```

검증:

```text
https://drive.example.com
https://drive.example.com/api/health
```

### 11단계: Gateway API 실행

외부 시스템 연동이 필요하면 Gateway API를 실행합니다.

예시:

```powershell
npm run gateway
```

필수 환경변수 예:

```env
GATEWAY_API_TOKEN=<API_TOKEN>
GATEWAY_FILE_ROOT=Wiki
```

검증:

```bash
curl http://localhost:8791/health
```

외부 공개가 필요하면 Cloudflare Tunnel로 별도 도메인을 연결합니다.

```text
api.example.com
→ http://localhost:8791
```

## 8. 주요 경로

### Windows

```text
C:\Users\<WINDOWS_USER>\Desktop\project\DIY_nas
C:\Users\<WINDOWS_USER>\nas-vm
C:\Users\<WINDOWS_USER>\nas-cloud-backups
```

### Ubuntu VM

```text
/home/<LINUX_USER>/nas-cloud/filebrowser
/home/<LINUX_USER>/nas-cloud/backups
/srv/nas/live/drive
```

### Docker

```text
FileBrowser Quantum: 8090 -> 80
Gateway API: 8791
```

### 공개 URL 예시

```text
https://drive.example.com
https://api.example.com
```

## 9. 공개 저장소 구성

권장 repo 구조:

```text
.
├─ README.md
├─ AGENTS.md
├─ AGENT_GUIDE.md
├─ .env.example
├─ docs/
│  ├─ public-pipeline-overview.ko.md
│  ├─ installation-sources.ko.md
│  ├─ glossary.ko.md
│  ├─ open-source-release-plan.md
│  └─ publication-sanitization-checklist.md
├─ scripts/
│  ├─ vm/
│  ├─ linux/
│  ├─ cloudflare/
│  ├─ gateway/
│  └─ backup/
├─ src/
│  └─ gateway server
├─ public/
│  ├─ index.html
│  └─ drive.html
├─ samples/
├─ tests/
└─ tools/
```

## 10. 공개 저장소에 절대 넣지 말아야 할 것

다음은 GitHub에 올리면 안 됩니다.

```text
.env
.env.local
token 파일
Cloudflare 인증 파일
Nextcloud app password
Gateway API token
실제 도메인 운영 토큰
실제 디스크 시리얼 전체 목록
백업 tar.gz
데이터베이스 파일
로그 파일
Ubuntu ISO
개인 문서
개인 이메일
개인 IP 구성
```

공개 문서에서는 다음처럼 치환합니다.

```text
실제 도메인       → example.com
실제 이메일       → user@example.com
Windows 사용자    → <WINDOWS_USER>
Linux 사용자      → <LINUX_USER>
API 토큰          → <API_TOKEN>
앱 비밀번호       → <APP_PASSWORD>
디스크 시리얼     → <DISK_SERIAL>
Tailscale IP      → 100.64.0.10
LAN IP            → 192.168.100.10
```

## 11. 검증 명령

### Windows

```powershell
npm run check
npm test
npm run audit:public
```

### Ubuntu VM

```bash
lsblk -f
zpool status
zfs list
df -h
docker ps
```

### FileBrowser Quantum

```bash
cd ~/nas-cloud/filebrowser
sudo docker compose ps
sudo docker logs --tail=100 nas-filebrowser-quantum
curl http://127.0.0.1:8090/api/health
```

### Cloudflare Tunnel

```text
Cloudflare Zero Trust
→ Networks
→ Connectors
→ Tunnel status: HEALTHY
```

외부 확인:

```bash
curl https://drive.example.com/api/health
```

### Gateway API

```bash
curl http://localhost:8791/health
curl https://api.example.com/health
```

## 12. 사용자와 권한 설계

권장 기본 사용자 그룹:

```text
admin
├─ 전체 관리

<WIKI_UPLOAD_USER>
├─ Wiki 첨부파일 업로드용
└─ integrations/wiki 또는 uploads/wiki만 접근

<LMS_UPLOAD_USER>
├─ LMS 첨부파일 업로드용
└─ integrations/lms 또는 uploads/lms만 접근

general_user
├─ 개인 폴더 또는 shared 일부만 접근
```

원칙:

- 관리자 계정은 자동화에 쓰지 않습니다.
- 외부 연동은 전용 계정과 전용 토큰을 씁니다.
- 업로드 권한과 삭제 권한은 분리하는 것이 좋습니다.
- 공개 공유 링크는 만료 시간과 비밀번호를 설정합니다.

## 13. 백업 전략

권장 백업 흐름:

```text
운영용 livepool
→ 정기 스냅샷
→ 백업 미러 또는 외부 백업 볼륨
→ 체크섬 생성
→ 복구 테스트
```

백업에서 중요한 것은 백업 파일을 만드는 것보다 복구가 실제로 되는지 확인하는 것입니다.

검증 예:

```bash
sha256sum -c SHA256SUMS.txt
```

또는 별도 테스트 위치에 압축을 풀어 파일 목록과 권한을 확인합니다.

## 14. 장애 대응 기준

### 운영용 디스크 1개 장애

상태:

```text
livepool mirror degraded
```

대응:

1. 서비스는 가능한 유지합니다.
2. 고장난 디스크를 식별합니다.
3. 새 디스크를 연결합니다.
4. ZFS replace/resilver를 수행합니다.
5. `zpool status`로 정상화 여부를 확인합니다.

### 운영용 저장소 전체 문제

대응:

1. 서비스를 중지합니다.
2. 백업 미러에서 최신 백업을 확인합니다.
3. 복구 대상 경로를 준비합니다.
4. 백업 압축을 해제하거나 스냅샷을 복원합니다.
5. 권한과 서비스 상태를 검증합니다.

### Cloudflare Tunnel 장애

확인:

```text
Tunnel status
Connector logs
Public hostname route
Origin service URL
```

주요 원인:

- origin URL 오타
- VM IP 변경
- FileBrowser 포트 변경
- cloudflared 서비스 중지
- DNS 레코드 충돌

### FileBrowser 500 오류

예시:

```text
500: could not get index
```

확인 순서:

```bash
cd ~/nas-cloud/filebrowser
sudo docker compose ps
sudo docker logs --tail=100 nas-filebrowser-quantum
ls -la /srv/nas/live/drive
df -h /srv/nas/live/drive
zpool status
zfs list
```

가능한 원인:

- `/srv/nas/live/drive`가 마운트되지 않음
- ZFS pool이 import되지 않음
- Docker bind mount가 깨짐
- FileBrowser source/index 이름 불일치
- FileBrowser database/config 경로 오류
- 컨테이너 권한 문제

## 15. 다른 에이전트에게 넘길 때의 규칙

이 프로젝트를 다른 Codex/Agent에게 맡길 때는 다음 문서를 먼저 읽게 합니다.

```text
AGENTS.md
AGENT_GUIDE.md
README.md
docs/public-pipeline-overview.ko.md
docs/installation-sources.ko.md
docs/glossary.ko.md
docs/publication-sanitization-checklist.md
```

에이전트 작업 규칙:

- 실제 상태는 추측하지 말고 명령으로 확인합니다.
- 디스크 작업 전에는 SSD와 HDD를 반드시 구분합니다.
- 파괴적 작업은 dry-run과 명시적 확인 플래그를 요구합니다.
- 토큰, 앱 비밀번호, 실제 도메인 인증값은 커밋하지 않습니다.
- 기능 변경 후에는 검증 명령을 실행합니다.
- 운영 문서와 공개 문서는 분리합니다.
- 개인 환경에서 검증한 값은 placeholder로 바꿉니다.

## 16. 이 프로젝트의 핵심 결정

최종 방향은 다음과 같습니다.

```text
Windows는 유지
Ubuntu Server는 Hyper-V VM으로 실행
OS는 SSD 위의 VM 디스크에 설치
운영 데이터는 HDD mirror에 저장
사람용 드라이브 UI는 FileBrowser Quantum
외부 시스템 연동은 Node Gateway API
외부 공개는 Cloudflare Tunnel
백업은 별도 mirror/백업 볼륨으로 분리
공개 저장소에는 개인정보와 secret을 넣지 않음
```

이 구조는 개인 NAS, 소규모 팀 드라이브, Wiki/LMS/글쓰기 사이트의 파일 저장소로 확장할 수 있습니다.

## 17. 앞으로의 개선 방향

우선순위:

1. FileBrowser Quantum source/index와 WebDAV 설정을 문서화합니다.
2. Gateway API와 FileBrowser API/WebDAV 연동 방식을 정리합니다.
3. 백업 복구 테스트를 자동화합니다.
4. Cloudflare Tunnel 설정 검증 스크립트를 추가합니다.
5. 사용자/그룹 권한 템플릿을 샘플로 제공합니다.
6. 실제 운영값을 `.env.example` 기반으로 안전하게 분리합니다.
7. 설치 스크립트는 dry-run과 명시적 destructive flag를 유지합니다.

## 18. 용어 요약

### NAS

네트워크로 접근하는 파일 저장 서버입니다.

### Hyper-V

Windows에서 가상 컴퓨터를 실행하는 기능입니다.

### Ubuntu Server

서버 운영에 많이 쓰이는 Linux 배포판입니다.

### ZFS

디스크 미러, 스냅샷, 데이터 무결성 확인에 강한 파일 시스템/볼륨 관리자입니다.

### ZFS mirror

같은 데이터를 두 디스크에 동시에 저장하는 방식입니다. 한 디스크가 고장나도 다른 디스크로 계속 운영할 수 있습니다.

### FileBrowser Quantum

서버 폴더를 웹브라우저에서 드라이브처럼 관리하게 해주는 셀프호스팅 파일 매니저입니다.

### Node Gateway API

Wiki, LMS, 글쓰기 사이트 같은 외부 시스템이 NAS 파일 저장소를 API로 쓰게 해주는 중간 서버입니다.

### Cloudflare Tunnel

로컬에서 실행 중인 서비스를 공인 HTTPS 주소로 안전하게 연결하는 터널입니다.

## 19. 공개 배포 전 최종 체크리스트

```text
[ ] README가 처음 보는 사람도 따라갈 수 있는가
[ ] 설치 순서가 Windows / Ubuntu / Cloudflare로 분리되어 있는가
[ ] .env.example만 있고 실제 .env는 없는가
[ ] 디스크 파괴 스크립트가 기본 실행으로 작동하지 않는가
[ ] 토큰, 비밀번호, 이메일, 실제 도메인, 실제 IP가 제거되었는가
[ ] 백업 파일과 DB 파일이 포함되지 않았는가
[ ] npm run audit:public 통과
[ ] npm run check 통과
[ ] npm test 통과
[ ] AGENT_GUIDE.md가 다른 에이전트 인계에 충분한가
```

## 20. 결론

이 프로젝트는 Windows PC를 유지하면서도 Linux 기반 NAS 서버를 구축하는 현실적인 구조입니다. 핵심은 Windows와 NAS 역할을 분리하고, 저장소는 미러와 백업으로 나누며, 사람용 UI와 시스템용 API를 분리하는 것입니다.

공개 저장소에서는 개인 환경의 실제값을 제거하고, 누구나 자신의 하드웨어와 도메인에 맞게 재현할 수 있는 설치 템플릿으로 관리하는 것이 목표입니다.
