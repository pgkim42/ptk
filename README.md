# PTK

PTK is a native macOS menu bar utility for keeping a local development machine readable and under control.

The first tool in PTK is a **local port monitor**. It watches a configurable set of development ports, shows which ones are currently listening, identifies the owning process when possible, and lets you terminate only the processes that can be verified safely.

PTK is currently a Swift-only macOS app. The old Rust/Tauri/Node runtime has been removed from the active product path; the app now builds and runs from the Swift Package under `macos/`.

## Status

- Platform: macOS 13+
- Runtime: Swift, AppKit, SwiftUI
- Entry point: `macos/`
- UI surface: menu bar status item with a compact utility panel
- Distribution: local development build only for now
- Scope: personal tool, maintained as a public repository

## What It Does

### Port Monitoring

PTK periodically scans the configured port expression and shows only the watched ports that are currently open.

The menu bar title shows the open watched-port count, such as `PTK 0` or `PTK 2`.

The panel can show:

- open watched-port count
- open port number
- PID, when exactly one listener can be identified
- process name, when available
- kill action only when the target is safe
- parse or lookup errors without hiding the rest of the panel

### Service Status

PTK also shows read-only status for common local development services:

| Service | Check |
| --- | --- |
| Docker | Docker daemon availability |
| PostgreSQL | port `5432` |
| MySQL | port `3306` |
| Redis | port `6379` |
| MongoDB | port `27017` |

These rows are status indicators only. PTK does not start, stop, restart, or manage Docker containers or database services.

### Safe Process Termination

PTK is intentionally conservative because killing a local process is destructive.

A kill action is available only when all of these are true:

1. The watched port is open.
2. Exactly one listener PID is known.
3. The process name is known.
4. The user confirms the native macOS confirmation alert.
5. Right before termination, PTK re-checks the port, PID, and process name.

If any of those checks fail, PTK blocks the kill. Ambiguous same-port listeners are left open but non-killable.

PTK sends `SIGTERM` only. It does not provide force kill, mismatch override, or best-effort termination for ambiguous listeners.

### Settings

The settings sheet supports:

- watched port expression editing
- validation before saving
- refresh interval selection: `1s`, `3s`, `5s`, `10s`
- persistence through `UserDefaults`

## Default Watched Ports

The default profile targets common local development servers:

| Range | Typical use |
| --- | --- |
| `3000-3009` | Next.js and similar dev servers |
| `5173-5182` | Vite dev servers |
| `4200-4209` | Angular dev servers |
| `8080-8089` | Spring Boot and similar backend servers |

Default expression:

```text
3000-3009,5173-5182,4200-4209,8080-8089
```

When changing the default profile, keep these files in sync:

- `README.md`
- `macos/Sources/PTKCore/Features/PortMonitor/Domain/AppDefaults.swift`
- related tests under `macos/Tests/PTKCoreTests/Features/PortMonitor/`

## Run

PTK is not packaged as an installer yet. Run it from the Swift package:

```bash
cd macos
swift run PTK
```

After launch, PTK appears in the macOS menu bar instead of opening a normal app window.

## Development

From the repository root:

```bash
cd macos && swift test
cd macos && swift build
cd macos && swift run PTK
```

For the Xcode scheme test path:

```bash
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

## Project Layout

```text
macos/
├── Package.swift
├── Sources/
│   ├── PTK/
│   │   └── executable entry point
│   ├── PTKApp/
│   │   ├── AppKit menu bar shell
│   │   ├── SwiftUI views
│   │   └── app-facing view model
│   └── PTKCore/
│       ├── Shell/
│       │   └── refresh scheduling
│       └── Features/
│           ├── PortMonitor/
│           │   ├── Domain/      # port expressions, menu model, port state
│           │   ├── Services/    # lsof/ps lookup, scan, kill safety
│           │   └── Settings/    # UserDefaults-backed settings
│           └── ServiceMonitor/
│               └── Services/    # Docker and local DB status checks
└── Tests/
    ├── PTKAppTests/
    └── PTKCoreTests/
```

## Design Principles

- Keep the runtime native: Swift, AppKit, and SwiftUI.
- Keep feature logic testable in `PTKCore`.
- Keep the menu bar surface compact and quick to scan.
- Treat process termination as fail-closed.
- Always confirm before killing.
- Always revalidate immediately before killing.
- Send `SIGTERM` only.
- Keep service status read-only.
- Do not add Rust, Tauri, Node, or a separate CLI runtime back into the app path.

## Testing Strategy

Tests do not terminate real processes. Kill behavior is covered with fake resolvers and fake terminators.

Current test coverage focuses on:

- port expression parsing
- default watched-port stability
- open-port filtering and sorting
- ambiguous listener handling
- kill confirmation and revalidation
- PID/process mismatch blocking
- refresh scheduling
- settings persistence and validation
- Docker and database status classification
- service command timeout handling
- app view model behavior

## Not In Scope Yet

PTK currently does not provide:

- installer packaging
- launch-at-login support
- notifications
- Docker container management
- database health queries
- remote host scanning
- force kill
- background service orchestration

## Public Repository Notes

This repository is intended to remain safe for public use.

- Do not commit API keys, tokens, passwords, private keys, or personal machine secrets.
- Keep local agent state such as `.omo/` and `.omx/` ignored.
- Prefer local settings or ignored files for machine-specific values.
- Avoid documenting private infrastructure or account details.

## License

No license file has been added yet. Add a `LICENSE` before treating PTK as reusable open-source software.

---

# PTK 한국어

PTK는 로컬 개발 환경을 빠르게 읽고 정리하기 위한 native macOS 메뉴 막대 유틸리티입니다.

현재 첫 번째 도구는 **로컬 개발 포트 모니터**입니다. 설정한 포트 범위를 감시하고, 열려 있는 개발 서버와 관련 프로세스를 보여주며, 안전하게 확인된 프로세스만 종료할 수 있게 합니다.

현재 PTK는 Swift 전용 macOS 앱입니다. 이전 Rust/Tauri/Node 런타임은 활성 제품 경로에서 제거했으며, 앱은 `macos/` 아래 Swift Package 하나로 빌드하고 실행합니다.

## 현재 상태

- 플랫폼: macOS 13 이상
- 런타임: Swift, AppKit, SwiftUI
- 진입점: `macos/`
- UI: 메뉴 막대 상태 항목과 compact utility panel
- 배포: 아직 설치 패키지 없음, 개발 빌드로 실행
- 저장소 성격: 개인용 도구이지만 공개 저장소 기준으로 관리

## 기능

### 포트 모니터링

PTK는 설정된 포트 표현식을 주기적으로 스캔하고, 감시 대상 중 현재 열려 있는 포트만 보여줍니다.

메뉴 막대 제목에는 `PTK 0`, `PTK 2`처럼 열린 감시 포트 수가 표시됩니다.

패널에서 확인할 수 있는 정보:

- 열린 감시 포트 수
- 열린 포트 번호
- 정확히 하나의 listener가 확인된 경우 PID
- 확인 가능한 경우 프로세스명
- 안전한 대상일 때만 표시되는 종료 action
- 포트 설정 오류나 조회 오류

### 서비스 상태

자주 확인하는 로컬 개발 서비스 상태도 읽기 전용으로 보여줍니다.

| 서비스 | 확인 방식 |
| --- | --- |
| Docker | Docker daemon 사용 가능 여부 |
| PostgreSQL | `5432` 포트 |
| MySQL | `3306` 포트 |
| Redis | `6379` 포트 |
| MongoDB | `27017` 포트 |

이 행들은 상태 표시만 담당합니다. PTK는 Docker container나 DB 서비스를 시작, 중지, 재시작, 관리하지 않습니다.

### 안전한 프로세스 종료

로컬 프로세스 종료는 파괴적인 동작이므로 PTK는 보수적으로 동작합니다.

종료 action은 다음 조건이 모두 맞을 때만 활성화됩니다.

1. 감시 포트가 열려 있어야 합니다.
2. listener PID가 정확히 하나여야 합니다.
3. 프로세스명을 확인할 수 있어야 합니다.
4. 사용자가 macOS native 확인 알림에서 승인해야 합니다.
5. 종료 직전에 포트, PID, 프로세스명을 다시 확인해야 합니다.

조건이 하나라도 깨지면 PTK는 종료를 차단합니다. 같은 포트에 listener가 모호하게 잡히면 열린 상태로 표시하되 종료할 수 없게 둡니다.

PTK는 `SIGTERM`만 보냅니다. force kill, mismatch override, 모호한 listener에 대한 추정 종료는 제공하지 않습니다.

### 설정

설정 sheet에서 다음을 바꿀 수 있습니다.

- 감시 포트 표현식
- 저장 전 유효성 검증
- 새로고침 주기: `1s`, `3s`, `5s`, `10s`
- `UserDefaults` 기반 설정 저장

## 기본 감시 포트

기본 프로파일은 흔한 로컬 개발 서버 포트를 대상으로 합니다.

| 범위 | 일반적인 용도 |
| --- | --- |
| `3000-3009` | Next.js 계열 개발 서버 |
| `5173-5182` | Vite 개발 서버 |
| `4200-4209` | Angular 개발 서버 |
| `8080-8089` | Spring Boot 계열 백엔드 서버 |

기본 표현식:

```text
3000-3009,5173-5182,4200-4209,8080-8089
```

기본 포트 프로파일을 바꾸면 다음 파일을 함께 갱신해야 합니다.

- `README.md`
- `macos/Sources/PTKCore/Features/PortMonitor/Domain/AppDefaults.swift`
- `macos/Tests/PTKCoreTests/Features/PortMonitor/` 아래 관련 테스트

## 실행

아직 설치 패키지는 없습니다. Swift Package에서 직접 실행합니다.

```bash
cd macos
swift run PTK
```

실행하면 일반 앱 창 대신 macOS 메뉴 막대에 PTK가 나타납니다.

## 개발

저장소 루트 기준:

```bash
cd macos && swift test
cd macos && swift build
cd macos && swift run PTK
```

Xcode scheme 테스트:

```bash
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

## 프로젝트 구조

```text
macos/
├── Package.swift
├── Sources/
│   ├── PTK/
│   │   └── 실행 파일 진입점
│   ├── PTKApp/
│   │   ├── AppKit 메뉴 막대 앱 셸
│   │   ├── SwiftUI views
│   │   └── app-facing view model
│   └── PTKCore/
│       ├── Shell/
│       │   └── 새로고침 스케줄링
│       └── Features/
│           ├── PortMonitor/
│           │   ├── Domain/      # 포트 표현식, 메뉴 모델, 포트 상태
│           │   ├── Services/    # lsof/ps 조회, 스캔, 종료 안전 로직
│           │   └── Settings/    # UserDefaults 기반 설정
│           └── ServiceMonitor/
│               └── Services/    # Docker와 로컬 DB 상태 확인
└── Tests/
    ├── PTKAppTests/
    └── PTKCoreTests/
```

## 설계 원칙

- 런타임은 Swift, AppKit, SwiftUI 기반 native 경로로 유지합니다.
- 기능 로직은 `PTKCore`에 두어 테스트 가능하게 유지합니다.
- 메뉴 막대 UI는 작고 빠르게 읽히는 도구로 유지합니다.
- 프로세스 종료는 fail-closed로 다룹니다.
- 종료 전에는 항상 사용자 확인을 거칩니다.
- 종료 직전에는 항상 대상을 재검증합니다.
- 종료 신호는 `SIGTERM`만 사용합니다.
- 서비스 상태는 읽기 전용으로 유지합니다.
- Swift 앱 런타임에 Rust, Tauri, Node, 별도 CLI 런타임을 다시 추가하지 않습니다.

## 테스트 전략

테스트는 실제 프로세스를 종료하지 않습니다. 종료 흐름은 fake resolver와 fake terminator로 검증합니다.

현재 주요 검증 영역:

- 포트 표현식 파싱
- 기본 감시 포트 안정성
- 열린 포트 필터링과 정렬
- 모호한 listener 처리
- 종료 확인과 재검증
- PID/process mismatch 차단
- 새로고침 스케줄링
- 설정 저장과 유효성 검증
- Docker와 DB 상태 분류
- 서비스 명령 timeout 처리
- 앱 view model 동작

## 아직 범위 밖인 것

현재 PTK는 다음 기능을 제공하지 않습니다.

- 설치 패키지
- 로그인 시 자동 실행
- 알림
- Docker container 관리
- DB health query 실행
- 원격 호스트 스캔
- force kill
- 백그라운드 서비스 오케스트레이션

## 공개 저장소 주의사항

이 저장소는 공개 상태를 유지할 수 있게 관리합니다.

- API key, token, password, private key, 개인 머신 secret을 커밋하지 않습니다.
- `.omo/`, `.omx/` 같은 로컬 agent 상태는 ignore합니다.
- 머신별 값은 로컬 설정이나 ignore된 파일을 사용합니다.
- 비공개 인프라나 개인 계정 정보는 문서에 적지 않습니다.

## 라이선스

아직 라이선스 파일이 없습니다. 외부에서 재사용 가능한 오픈소스로 다루려면 `LICENSE`를 추가해야 합니다.
