# PTK macOS Swift app

이 디렉터리는 PTK의 native macOS Swift 앱입니다. 앱은 Swift Package로 구성되어 있으며, AppKit `NSStatusItem` 기반 메뉴 막대 실행 파일과 테스트 가능한 `PTKCore` 모듈을 포함합니다.

## 구성

- `PTKApp`: AppKit 메뉴 막대 앱 셸 진입점
- `PTKCore/Shell`: AIO 상태바 앱 공통 로직
- `PTKCore/Features/PortMonitor`: 포트 파싱, 스캔, 프로세스 조회, 종료 안전 로직
- `PTKCore/Features/ServiceMonitor`: Docker daemon과 주요 로컬 DB 포트 상태 표시 로직
- `PTKCoreTests`: core 단위 테스트

## UI 동작

메뉴 막대 패널은 열린 감시 포트를 compact row로 보여줍니다. 포트 번호와
PID는 지역화 콤마 없이 표시하고, 프로세스는 긴 경로 대신 실행 파일명을
우선 표시합니다. 전체 프로세스 경로 또는 명령은 hover 도움말과 상세 복사
action에 남겨 둡니다.

서비스 상태 행은 읽기 전용 지표이며, 중지 상태는 로컬 개발 환경에서 흔한
상태이므로 경고보다 낮은 톤으로 표시합니다.

## 런타임 경계

이 앱은 Swift/AppKit만 사용합니다. Rust, Tauri, Node, 별도 CLI 스택에 의존하지 않습니다.

## 빌드 및 테스트

저장소 루트에서 실행:

```bash
cd macos && swift test
cd macos && swift build
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

개발 실행:

```bash
cd macos && swift run PTK
```

실행 제품 이름은 `PTK`입니다.
