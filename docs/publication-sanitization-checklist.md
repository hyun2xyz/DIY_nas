# 공개 전 정리 체크리스트

GitHub에 공개하기 전에 아래 항목을 확인합니다.

## 반드시 제외할 파일

- `.env`
- `.env.local`
- API token 파일
- app password 파일
- Cloudflare Tunnel token 또는 credential 파일
- 실제 백업 압축 파일
- 데이터베이스 파일
- 로그 파일
- 다운로드한 ISO 또는 설치 파일
- 개인 운영 문서
- 실제 디스크 인벤토리 문서

## 반드시 치환할 값

- 실제 도메인 → `example.com`
- 실제 이메일 → `user@example.com`
- 실제 내부 IP → `192.168.100.10`
- 실제 Tailscale IP → `100.64.0.10`
- 실제 Windows 사용자 경로 → `C:\Users\<WINDOWS_USER>`
- 실제 Linux 사용자명 → `<LINUX_USER>`
- 실제 디스크 시리얼 → `<DISK_SERIAL>`
- 실제 API token → `<API_TOKEN>`
- 실제 app password → `<APP_PASSWORD>`

## 스크립트 안전 기준

- 디스크 초기화 스크립트는 대상 디스크를 출력해야 합니다.
- 파괴적 작업은 명시적 플래그 없이는 실행하지 않아야 합니다.
- 기본 예시는 실제 운영 디스크 이름을 포함하지 않아야 합니다.
- 공개 스크립트에는 실제 계정명, 도메인, 토큰이 없어야 합니다.

## 검증 명령

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run audit:public
```

## 수동 검색

감사 스크립트 외에도 아래 항목을 수동으로 검색합니다.

```powershell
rg -n "password|token|secret|credential|private" .
rg -n "example.com|user@example.com|<API_TOKEN>|<APP_PASSWORD>" .
```

첫 번째 검색은 실제 비밀값이 들어갔는지 확인하기 위한 것이고, 두 번째 검색은 placeholder가 의도대로 남아 있는지 확인하기 위한 것입니다.

## 공개 후 확인

- GitHub에서 파일 목록을 직접 확인합니다.
- `.env`가 올라가지 않았는지 확인합니다.
- Issues/README에 실제 운영 주소가 노출되지 않았는지 확인합니다.
- 설치 가이드가 공개 템플릿 기준으로만 동작하는지 확인합니다.
