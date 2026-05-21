# 용어 정리

이 문서는 NAS 파이프라인에서 자주 나오는 용어를 짧게 설명합니다.

## Ubuntu

Linux 배포판 중 하나입니다. 서버 운영에 많이 쓰이며 Docker, ZFS, 자동화 스크립트 같은 서버 도구를 설치하기 쉽습니다. 이 프로젝트에서는 Windows를 지우지 않고 Hyper-V 가상 머신 안에서 Ubuntu Server를 실행합니다.

## Hyper-V

Windows에 포함된 가상화 기능입니다. Windows 안에서 Ubuntu 같은 다른 운영체제를 VM으로 실행할 수 있습니다. 이 구조에서는 Windows는 평소처럼 쓰고, NAS 서버 기능은 Hyper-V 안의 Ubuntu가 담당합니다.

## VM

Virtual Machine의 약자입니다. 실제 컴퓨터 안에서 돌아가는 가상 컴퓨터입니다. Ubuntu VM은 자체 CPU, 메모리, 디스크, 네트워크를 가진 것처럼 동작합니다.

## SSD와 HDD 역할

SSD는 운영체제와 VM 시스템 디스크처럼 빠른 응답이 필요한 영역에 적합합니다. HDD는 대용량 파일 보관에 적합합니다. 이 프로젝트에서는 Ubuntu OS는 SSD 쪽 VM 디스크에 두고, NAS 데이터는 별도 HDD에 둡니다.

## ZFS

파일시스템과 볼륨 관리 기능을 함께 제공하는 저장소 기술입니다. mirror, snapshot, checksum 같은 기능이 강점입니다.

## ZFS live mirror

운영 데이터가 저장되는 HDD 2개 mirror입니다. 같은 데이터가 두 디스크에 기록되므로 디스크 하나가 고장나도 서비스가 계속될 수 있습니다. 다만 실수로 삭제한 파일도 함께 삭제되므로 backup mirror를 따로 둡니다.

## Backup mirror

운영 데이터의 백업을 저장하는 별도 mirror입니다. live mirror와 목적이 다릅니다. live mirror는 서비스 지속성을 위한 것이고, backup mirror는 복구를 위한 것입니다.

## Docker

애플리케이션을 컨테이너로 실행하는 도구입니다. FileBrowser Quantum, Gateway 같은 서버 프로그램을 설치 파일로 직접 깔지 않고 격리된 컨테이너로 실행할 수 있습니다.

## Docker Compose

여러 Docker 컨테이너를 하나의 YAML 파일로 정의하고 실행하는 도구입니다. `docker compose up -d`로 서비스를 백그라운드 실행할 수 있습니다.

## FileBrowser Quantum

서버 폴더를 웹 브라우저에서 파일 관리자처럼 사용할 수 있게 해주는 셀프호스팅 파일 매니저입니다. 이 프로젝트에서는 최종 사용자용 웹 드라이브 UI로 사용합니다.

## Nextcloud

파일, 캘린더, 연락처, 협업 앱까지 포함하는 셀프호스팅 클라우드 플랫폼입니다. 기능은 많지만 상대적으로 무겁습니다. 이 프로젝트에서는 웹 드라이브 UI를 FileBrowser Quantum으로 단순화하고, Nextcloud는 필요 시 비교/이전 대상으로만 봅니다.

## Node Gateway

Node.js로 만든 얇은 API 서버입니다. 외부 사이트가 파일을 업로드하거나 다운로드할 때 중간에서 인증, 경로 검증, 저장소 호출을 처리합니다. 사람용 UI가 아니라 시스템 연동용 계층입니다.

## Cloudflare Tunnel

로컬 서버를 공개 HTTPS 주소에 연결하는 Cloudflare 기능입니다. 공유기 포트포워딩 없이 `https://drive.example.com` 같은 주소를 내부 서비스로 연결할 수 있습니다.

## Tailscale

장치끼리 사설 네트워크처럼 연결해주는 VPN 계열 도구입니다. 내 노트북, Windows PC, 서버가 같은 사설망에 있는 것처럼 접근할 수 있습니다. 공개 웹 주소가 필요 없는 내부 테스트에 유용합니다.

## WebDAV

HTTP 기반 파일 접근 프로토콜입니다. Finder, Windows 탐색기, 일부 앱에서 원격 파일 저장소를 드라이브처럼 붙여 사용할 수 있습니다.

## API token

API 요청이 허용된 사용자나 서비스에서 온 것인지 확인하는 비밀값입니다. 코드에 하드코딩하지 않고 `.env`나 서버 환경변수로만 보관해야 합니다.

## App password

서비스 계정이 외부 앱이나 API에서 로그인할 때 쓰는 별도 비밀번호입니다. 일반 로그인 비밀번호와 분리해서 관리하고, 유출되면 해당 app password만 폐기할 수 있게 합니다.
