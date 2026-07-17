# PTK macOS Swift app

이 디렉터리는 PTK의 native macOS Swift 앱입니다. 앱은 Swift Package로 구성되어 있으며, AppKit `NSStatusItem` 기반 메뉴 막대 실행 파일과 테스트 가능한 `PTKCore` 모듈을 포함합니다.

## 구성

- `PTKApp`: AppKit 메뉴 막대 앱 셸 진입점
- `PTKCore/Shell`: PTK 메뉴 막대 앱 공통 로직
- `PTKCore/Features/PortMonitor`: 포트 파싱, 스캔, 프로세스 조회, 종료 안전 로직
- `PTKCore/Features/ServiceMonitor`: Docker daemon, Docker published port, 주요 로컬 DB 포트 상태 표시 로직
- `PTKCoreTests`: core 단위 테스트
- `PTKAppTests`: 앱 통합, 알림 조정, 네이티브 알림 클라이언트, 접근성 테스트

## UI 동작

메뉴 막대 패널은 열린 감시 포트를 compact row로 보여줍니다. 포트 번호와
PID는 지역화 콤마 없이 표시하고, 프로세스는 긴 경로 대신 실행 파일명을
우선 표시합니다. 전체 프로세스 경로 또는 명령은 hover 도움말과 상세 복사
action에 남겨 둡니다.

서비스 상태 행은 읽기 전용 지표이며, 중지 상태는 로컬 개발 환경에서 흔한
상태이므로 경고보다 낮은 톤으로 표시합니다.

Docker daemon이 실행 중이면 Docker 행 아래에 host에 publish된 container
포트를 읽기 전용 하위 행으로 표시합니다. 단일 숫자 host 포트는
`http://localhost:<port>`로 복사할 수 있지만, range/요약/숨김/모호한
다중 포트 행은 복사 action을 노출하지 않습니다. 하위 행은 stop/kill
action과 연결하지 않고, Services running/total 카운터에도 포함하지
않습니다. 포트 표기는 `host -> container` 형식을 유지합니다.

저장된 감시 포트 프로필은 패널에서 빠르게 전환할 수 있고, 사용자 정의
서비스는 기본 서비스와 구분되는 read-only 그룹으로 표시합니다. 사용자 정의
서비스가 없으면 Settings 안내 help 행만 표시합니다. 종료할 수
없는 포트는 ambiguous listener, PID/process 누락, mismatch 같은 이유와
다음 확인 힌트를 보여주되 새 종료 옵션은 만들지 않습니다.

패널이 열려 있으면 사용자가 고른 새로고침 주기를 유지하고, 패널이 닫히면
모든 사용자 선택 가능 주기보다 느린 내부 quiet 주기로 전환합니다.

## 포트 변경 알림

`0.6.0` 릴리스 준비에서는 포트 변경 알림을 새 설치와 업데이트 설정에서 기본으로
끈 상태로 제공합니다. 이 버전은 아직 출시되지 않았으며, `0.5.0`이 최신 공개
배포 버전으로 남아 있습니다. 처음 켤 때는 알림 포트 표현식이 비어 있는 경우에만 감시
포트 표현식을 복사하고, 그 뒤에는 두 표현식을 독립적으로 유지합니다. 두
표현식은 쉼표·범위 문법과 5,000포트 파서 제한을 함께 쓰며, 알림을 보내려면
포트가 현재 두 표현식의 교집합에 있어야 합니다.

신뢰할 수 있는 열림/닫힘 전환만 대상으로 하며, 양수인 단일 PID는 프로세스
이름을 알 수 없어도 알릴 수 있습니다. 첫 스캔, 신뢰할 수 없거나 일시적인 상태,
프로세스 식별 정보만 바뀐 경우와 모호한 결과, 조회 실패, listener 근거 누락은
제외합니다. 성공적으로 전달한 뒤 같은 포트와 같은 방향의 알림은 10초 동안
막고, 반대 방향은 즉시 보냅니다. 알림 기록을 따로 저장하지 않습니다.

시작, 다시 활성화, Settings 표시, 전달 전의 권한 상태 확인은 권한 요청을 절대
띄우지 않습니다. macOS 권한 요청은 권한 상태가 미결정일 때 유효한 켜기 설정을
저장한 뒤에만 할 수 있습니다. 막힌 권한은 macOS Settings로 연결하며, 권한이
거부되거나 막혀도 저장한 켜기 상태와 포트 표현식은 유지합니다. 알림을 누르면
PTK 패널만 엽니다.

## 런타임 경계

이 앱은 Swift/AppKit만 사용합니다. Rust, Tauri, Node, 별도 CLI 스택에 의존하지 않습니다.
프로세스 종료는 재검증 뒤 `SIGTERM`만 사용합니다. 모호하거나 달라진 대상은 종료하지 않습니다.

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
