# Moving Wallpaper Marketplace Server

간단한 자체호스팅 마켓플레이스 서버입니다. 외부 패키지 없이 Node.js 기본 모듈만 사용합니다.

## 실행

별도 터미널에서 서버를 켜려면 프로젝트 루트에서 아래 명령을 실행합니다. 마켓플레이스를 쓰는 동안 이 터미널을 열어 둡니다.

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
./scripts/start-marketplace-server.sh
```

끄려면 서버 터미널에서 `Control-C`를 누르거나 아래 명령을 실행합니다.

```bash
./scripts/stop-marketplace-server.sh
```

터미널에 붙여서 직접 실행하려면 아래 명령을 사용합니다.

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac/marketplace-server
node server.js
```

기본 주소는 아래와 같습니다.

```text
http://127.0.0.1:8787
```

같은 네트워크의 다른 기기에서도 접근하게 하려면 아래처럼 실행합니다.

```bash
HOST=0.0.0.0 PORT=8787 node server.js
```

## 앱에서 사용

1. 서버를 켭니다.
2. Moving Wallpaper 앱의 `Profile` 탭에서 표시 이름을 입력하고 로그인합니다.
3. `Marketplace` 서버 주소에 `http://127.0.0.1:8787`을 입력합니다.
4. `새로고침`을 누릅니다.
5. `받기`를 누르면 앱 라이브러리에 추가됩니다.
6. `받고 적용`을 누르면 다운로드 후 바로 배경으로 실행됩니다.

현재 선택된 로컬 동영상 또는 GIF는 `업로드` 버튼으로 서버에 올릴 수 있습니다. 업로드한 항목에는 프로필의 작성자 이름과 ID가 함께 저장됩니다.

## 저장 위치

- 메타데이터: `data/wallpapers.json`
- 업로드 파일: `data/files/`

## API

- `GET /api/wallpapers`: 업로드된 배경 목록
- `POST /api/wallpapers`: `multipart/form-data` 업로드
  - `title`: 제목
  - `kind`: `video` 또는 `gif`
  - `uploaderName`: 업로드한 사용자 표시 이름
  - `uploaderID`: 업로드한 사용자 ID
  - `file`: `.mp4`, `.mov`, `.m4v`, `.webm`, `.avi`, `.gif`
- `GET /files/:storedName`: 파일 다운로드

## 주의

이 서버는 개발/개인용 샘플입니다. 앱의 프로필 값은 작성자 표시용 메타데이터이며, 실제 계정 인증, 권한, 업로드 검수, 악성 파일 검사, HTTPS, 저장 용량 관리가 없습니다. 외부 인터넷에 공개하려면 인증, HTTPS 프록시, 파일 검사, 용량 제한, 백업 정책을 추가해야 합니다.
