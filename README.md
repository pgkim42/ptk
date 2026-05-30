# PTK

PTK는 로컬 개발 중 열려 있는 개발 서버 포트를 감시하고, 점유 중인 프로세스를 안전하게 확인·종료하기 위한 macOS 메뉴 막대 도구입니다.

현재 구현은 **native Swift/AppKit 앱**입니다. 이전 Rust/Tauri/CLI 스택은 저장소에서 제거했고, 런타임과 빌드 경로는 Swift Package 하나로 단순화했습니다.

## 현재 상태

- 현재 버전: `v0.4-swift-migration`
- 구현 위치: `macos/`
- UI: AppKit `NSStatusItem` 기반 메뉴 막대 앱
- 지원 대상: macOS 13 이상
- 런타임 경계: Swift 앱은 Rust, Tauri, Node, CLI 스택에 의존하지 않습니다.

## 하는 일

PTK는 지정된 포트 범위를 주기적으로 확인해 다음 정보를 메뉴 막대에서 보여줍니다.

- 현재 열려 있는 감시 대상 포트 수
- 열린 포트 목록
- 포트를 점유한 PID
- 프로세스명
- Docker daemon 상태
- 주요 로컬 DB 서비스 포트 상태: PostgreSQL, MySQL, Redis, MongoDB
- 수동 새로고침
- 새로고침 주기 선택
- 안전한 프로세스 종료 요청

프로세스 종료는 즉시 실행하지 않습니다. 사용자의 확인을 받은 뒤, 종료 직전에 포트·PID·프로세스명을 다시 확인하고, 대상이 바뀌었거나 모호하면 종료를 차단합니다.

## 기본 감시 포트

Swift 앱의 기본 감시 포트는 README와 Swift 상수, 테스트가 서로 동기화되어야 합니다.

| 범위 | 용도 |
| --- | --- |
| `3000-3009` | Next.js 계열 개발 서버 |
| `5173-5182` | Vite 계열 개발 서버 |
| `4200-4209` | Angular 계열 개발 서버 |
| `8080-8089` | Spring Boot 계열 개발 서버 |

기본 표현식:

```text
3000-3009,5173-5182,4200-4209,8080-8089
```

기본 포트 프로파일을 바꾸면 다음 위치를 함께 갱신해야 합니다.

- `README.md`
- `macos/Sources/PTKCore/Features/PortMonitor/Domain/AppDefaults.swift`
- `macos/Tests/PTKCoreTests/Features/PortMonitor/Domain/PortRangeParserTests.swift`

## 프로젝트 구조

```text
macos/
├── Package.swift
├── Sources/
│   ├── PTKApp/      # AppKit 메뉴 막대 앱 셸 진입점
│   └── PTKCore/     # Shell 공통 로직과 Features/* 도구 로직
└── Tests/
    ├── PTKAppTests/
    └── PTKCoreTests/
```

## Swift 메뉴 막대 앱 동작

- 메뉴 막대 제목에 열린 감시 포트 수 표시
- 열린 포트만 메뉴 row로 표시
- PID와 프로세스명을 확인할 수 있을 때만 종료 action 활성화
- 같은 포트에 여러 PID가 매핑되는 모호한 listener는 종료 비활성화
- 새로고침 주기 프리셋 제공: `1s`, `3s`, `5s`, `10s`
- 선택한 새로고침 주기는 `UserDefaults`에 저장
- Docker/DB 서비스 상태는 읽기 전용으로 표시
- 종료는 `SIGTERM`만 사용
- force kill 또는 mismatch override는 제공하지 않음

## 실행 및 검증

### 테스트

```bash
cd macos
swift test
```

### 빌드

```bash
cd macos
swift build
```

### Xcode 테스트

```bash
cd macos
xcodebuild -scheme PTK -destination 'platform=macOS' test
```

### 개발 실행

```bash
cd macos
swift run PTK
```

실행하면 일반 창 대신 macOS 상단 메뉴 막대에 `PTK 0` 같은 상태 항목이 나타납니다.

## 종료 안전 정책

PTK의 Swift 앱은 프로세스 종료를 보수적으로 처리합니다.

1. 메뉴 row에 안전한 종료 대상이 있어야 합니다.
   - 포트가 열려 있어야 함
   - PID가 있어야 함
   - 프로세스명이 있어야 함
   - 같은 포트에 여러 PID가 걸린 모호한 상태가 아니어야 함
2. 사용자가 native 확인 알림에서 종료를 승인해야 합니다.
3. 종료 직전에 포트의 현재 프로세스를 다시 조회합니다.
4. 다음 경우 종료를 차단합니다.
   - 포트가 더 이상 열려 있지 않음
   - PID가 바뀜
   - 프로세스명이 바뀜
   - 프로세스명을 확인할 수 없음
   - 같은 포트의 listener가 모호함
5. 통과한 경우에만 `SIGTERM`을 보냅니다.

테스트에서는 실제 프로세스를 종료하지 않습니다. 종료 로직은 fake resolver와 fake terminator를 통해 검증합니다.

## 개발 원칙

- 변경은 가능한 한 작게 유지합니다.
- Swift 앱 런타임에 Rust/Tauri/Node 의존성을 추가하지 않습니다.
- 기본 포트 프로파일을 바꾸면 README와 코드 상수를 함께 갱신합니다.
- 종료 관련 변경은 반드시 테스트로 안전 조건을 먼저 고정합니다.
