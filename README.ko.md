<p align="center">
  <img src="public/diynas.jpg" alt="DIY_nas 라인 아트: 노트북과 홈 서버가 연결된 그림" width="780">
</p>

〈DIY_nas〉는 Windows를 지우지 않고 그대로 유지한 상태에서, Windows PC 안에 Linux 기반 NAS 드라이브를 구성하는 공개용 템플릿입니다. 

English documentation: [README.md](README.md)

## 작업노트

안녕하세요, 현입니다.

저는 한국에서 편집디자인을 공부하며 AI를 활용한 다양한 파이프라인을 연구하고, 사람들과 공유하는 일을 하고 있어요. 월드와이드웹의 공유 철학과 HTML과 유머 그리고 글짓기를 사랑합니다. HTML과 CSS, JavaScript가 아닌 개발을 본격적으로 시작한 지는 이제 한 달 정도 되었어요.

제 첫 오픈소스 프로젝트인〈DIY_nas〉를 소개합니다.

저는 작년부터 디자이너와 창작자들을 위한 생성형 AI 튜토리얼 워크숍을 꾸준히 진행해 왔는데요. 최근에는 ‘기록’의 중요성을 크게 느끼면서, 위키 엔진을 기반으로 더 많은 사람들이 접근할 수 있는 〈iyo_wiki〉를 만들고 있었습니다. 이곳에서 제 작업 과정과 생각을 공유하기도 하고, AI 관련 인터뷰를 번역하고, 위키 사용자들끼리의 작은 모임이나 프로젝트 오픈콜도 열고, 각자가 위키 페이지를 제작해서 지식의 공유를 실천하는 공간으로도 기능하고, 여건상 제 워크숍 공간에 오지 못하는 먼 친구들을 위한 VOD 시스템도 함께 만들고 싶었고요.

NAS에 대해 조금 공부해보니, 리눅스 기반의 OS가 구동되는 하드웨어가 필요하고, 안정적인 운영을 위해서 레이드 시스템으로 4Bay는 필요하고, HDD도 나스용을 별도로 구매해야 했구요. 그럼 벌써 비용이 어마어마하게 불어나는데요. 문득 ‘작업실에 놀고 있는 사양 좋은 데스크탑으로 만들면 되는거 아닌가?’ 라는 생각에서 가볍게 시작했어요. 안드레 카파시의 바이브 코딩으로 오로지 자연어로만 프로젝트를 진행했는데 한가지 큰 제약으로 진행 중 모르는 단어가 나오면 그냥 넘기지 않고, 그 개념과 원리를 시간을 들여 공부하고 정리했습니다. 내가 지금 뭘 하고 있는지 파악해야 하니까요.

병렬로 진행하던 프로젝트들이 몇 개 있어서 총 작업 시간은 일주일 정도 걸린 것 같습니다. 집중해서 했다면 더 빨리도 가능했을 것 같아요. 아직은 베타 테스트 단계지만, 위키에 업로드되는 클라우드로 테스트를 시작했고 제가 구축한 파이프라인을 깃허브에 알기 쉽게 공유합니다.


프로젝트에 대한 피드백과 제안은 언제나 환영합니다.
읽어주셔서 감사합니다. 아주 많이 행복하세요.


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
