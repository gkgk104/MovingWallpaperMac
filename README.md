# Moving Wallpaper Mac

macOS에서 움직이는 배경화면처럼 동작하는 네이티브 SwiftUI 앱입니다. Wallpaper Engine의 핵심 흐름을 macOS에서 가능한 범위로 벤치마킹해 로컬 라이브러리, 영상/GIF/웹 배경, 재생목록, 멀티 모니터, 성능 정책, 자체호스팅 마켓플레이스를 넣었습니다.

macOS는 공개 API로 시스템 배경화면 자체를 동영상으로 바꾸는 기능을 제공하지 않습니다. 이 앱은 모든 디스플레이에 마우스 이벤트를 무시하는 데스크톱 레벨 창을 깔고, 그 안에서 샘플 모션 또는 선택한 동영상을 반복 재생합니다.

## 빌드

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

빌드가 끝나면 `dist/Moving Wallpaper.app`이 생성됩니다.

## 사용

1. 앱을 실행합니다.
2. `Profile` 탭에서 표시 이름을 입력하고 로그인합니다.
3. `Library`에서 기본 모션 프리셋을 선택하거나 `Media`로 `.mov`, `.mp4`, `.gif` 파일을 추가합니다.
4. 웹 배경은 URL 입력칸에 `https://...` 주소를 넣고 `+`를 누릅니다.
5. `Marketplace`에서 서버 주소를 넣고 `새로고침`을 누르면 업로드된 배경을 받을 수 있습니다.
6. 받은 항목은 자동으로 `Library`에 추가되며, `받고 적용`을 누르면 바로 배경으로 실행됩니다.
7. `시작`을 누릅니다.
8. 원래 배경으로 돌아가려면 `정지`를 누르거나 앱을 종료합니다.

## 마켓플레이스 서버

별도 터미널에서 서버를 켜려면 아래 명령을 실행합니다. 마켓플레이스를 쓰는 동안 이 터미널을 열어 둡니다.

```bash
cd /Users/leehyunbin/codes/MovingWallpaperMac
./scripts/start-marketplace-server.sh
```

끄려면 서버 터미널에서 `Control-C`를 누르거나 아래 명령을 실행합니다.

```bash
./scripts/stop-marketplace-server.sh
```

직접 실행하려면 `marketplace-server` 폴더에서 `node server.js`를 실행하면 됩니다.

## 기능

- 모션 프리셋: Aurora Ribbons, Orbit Flow, Signal Mesh
- 팔레트 변경: Aurora, Ember, Graphite, Prism
- 로컬 동영상 라이브러리 추가
- GIF 애니메이션 파일 추가
- 웹 URL 배경 추가
- 자체호스팅 마켓플레이스 서버
- 로컬 프로필 로그인과 작성자 표시
- 마켓플레이스 업로드, 다운로드, 바로 적용
- 받은 배경 라이브러리 자동 저장
- 모든 모니터 또는 메인 모니터 적용
- 채우기/맞춤 비디오 비율
- 재생목록 순환과 수동 다음 항목 이동
- 성능 프로필: 품질, 균형, 절전
- 성능 정책: 항상 재생, 큰 창이면 일시정지, 큰 창이면 정지

## 참고

- 앱이 실행 중일 때만 움직이는 배경화면이 유지됩니다.
- 서명되지 않은 로컬 앱 실행 경고가 나오면 Finder에서 앱을 우클릭한 뒤 `열기`를 선택하세요.
- 전체 화면 Space나 일부 데스크톱 관리 앱에서는 macOS의 창 레벨 정책에 따라 보이는 방식이 달라질 수 있습니다.
- GIF는 AppKit 이미지 뷰로 표시되며, `채우기`/`맞춤` 비율 설정을 따릅니다.
- 웹 배경은 보안 정책과 사이트별 자동재생 제한에 영향을 받을 수 있습니다.
- 마켓플레이스는 `marketplace-server/`에 있는 간단한 Node.js 서버입니다. 프로필 로그인은 업로드 작성자 표시용 로컬 프로필이며, 운영용 인증, 검수, 결제 기능은 포함하지 않았습니다.

자세한 사용법은 `USER_GUIDE.md`를 참고하세요.
