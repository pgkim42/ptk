# PTK

PTK는 로컬 개발 환경을 빠르게 확인하고 정리하기 위한 개인용 macOS 메뉴 막대 도구입니다. 현재 첫 번째 도구는 **개발 포트 감시/정리**이며, 지정한 포트 범위에서 열려 있는 서버와 관련 프로세스를 보여주고 안전한 종료 흐름을 제공합니다.

현재 구현은 **native Swift/AppKit 앱**입니다. 이전 Rust/Tauri/CLI 스택은 제거했고, 런타임과 빌드 경로는 `macos/` 아래 Swift Package 하나로 단순화했습니다.

## 현재 상태

- 버전 성격: Swift/AppKit 기반 v0.4 라인
- 구현 위치: `macos/`
- UI: AppKit `NSStatusItem` 메뉴 막대 앱
- 지원 대상: macOS 13 이상
- 런타임 경계: Swift 앱은 Rust, Tauri, Node, 별도 CLI 스택에 의존하지 않습니다.
- 저장소 성격: 개인용 도구이지만 코드와 문서는 공개 저장소 기준으로 관리합니다.

## 주요 기능

### 포트 모니터링

PTK는 설정된 포트 표현식을 주기적으로 파싱하고, 각 포트가 로컬에서 listening 중인지 확인합니다. 메뉴 막대 제목에는 열린 감시 대상 포트 수가 표시되고, 메뉴에는 열린 포트만 row로 나타납니다.

표시 정보:

- 열린 감시 대상 포트 수
- 열린 포트 번호
- 포트를 점유한 PID
- 프로세스명
- 프로세스 조회 실패 또는 모호한 listener 상태

### 서비스 상태 표시

개발할 때 자주 확인하는 로컬 서비스 상태를 읽기 전용으로 보여줍니다.

- Docker daemon 상태
- PostgreSQL 기본 포트 `5432`
- MySQL 기본 포트 `3306`
- Redis 기본 포트 `6379`
- MongoDB 기본 포트 `27017`

서비스 상태는 참고 정보입니다. PTK는 Docker나 DB 프로세스를 직접 시작하거나 종료하지 않습니다.

### 안전한 프로세스 종료

포트 row에 안전한 종료 대상이 있을 때만 종료 action이 활성화됩니다. 종료 요청은 즉시 실행되지 않고, 사용자 확인과 종료 직전 재검증을 거칩니다.

종료 조건:

1. 포트가 열려 있어야 합니다.
2. PID를 정확히 하나 확인할 수 있어야 합니다.
3. 프로세스명을 확인할 수 있어야 합니다.
4. 사용자가 native 확인 알림에서 종료를 승인해야 합니다.
5. 종료 직전에 포트·PID·프로세스명이 처음 표시된 대상과 일치해야 합니다.

위 조건이 하나라도 깨지면 종료를 차단합니다. 통과한 경우에만 `SIGTERM`을 보냅니다. force kill, mismatch override, 모호한 listener 강제 종료는 제공하지 않습니다.

### 새로고침과 설정

- 수동 새로고침
- 새로고침 주기 선택: `1s`, `3s`, `5s`, `10s`
- 선택한 새로고침 주기 `UserDefaults` 저장
- 감시 포트 표현식 편집
- 유효하지 않은 포트 표현식 저장 차단

## 기본 감시 포트

기본 포트 프로파일은 일반적인 로컬 개발 서버 포트를 대상으로 합니다.

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

## 설치 및 실행

현재 별도 릴리스 빌드나 패키지 배포는 없습니다. 개발 모드로 직접 실행합니다.

```bash
cd macos
swift run PTK
```

실행하면 일반 창 대신 macOS 상단 메뉴 막대에 `PTK 0` 같은 상태 항목이 나타납니다.

## 개발 명령

저장소 루트 기준:

```bash
cd macos && swift test
cd macos && swift build
cd macos && swift run PTK
```

Xcode 기반 테스트가 필요하면 다음 명령을 사용합니다.

```bash
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

## 프로젝트 구조

```text
macos/
├── Package.swift
├── Sources/
│   ├── PTKApp/
│   │   └── AppKit NSStatusItem 앱 셸
│   └── PTKCore/
│       ├── Shell/
│       │   └── 상태바 앱 공통 스케줄링 로직
│       └── Features/
│           ├── PortMonitor/
│           │   ├── Domain/      # 포트 표현식, 메뉴 모델, 포트 상태
│           │   ├── Services/    # lsof/ps 조회, 포트 스캔, 종료 안전 로직
│           │   └── Settings/    # UserDefaults 기반 설정
│           └── ServiceMonitor/
│               └── Services/    # Docker/DB 서비스 상태 조회
└── Tests/
    ├── PTKAppTests/
    └── PTKCoreTests/
```

## 설계 원칙

PTK는 작은 메뉴 막대 앱이지만, 프로세스 종료 기능을 포함하므로 보수적인 구조를 유지합니다.

- UI는 AppKit `NSStatusItem` 기반으로 유지합니다.
- core 로직은 `PTKCore`에서 테스트 가능하게 분리합니다.
- 포트 종료는 항상 확인, 재검증, mismatch 차단을 거칩니다.
- 종료 신호는 `SIGTERM`만 사용합니다.
- 서비스 상태는 읽기 전용 관찰 정보로 유지합니다.
- Swift 앱 런타임에 Rust/Tauri/Node 의존성을 추가하지 않습니다.
- 기능 추가 시 `Features/*` 아래에 경계를 명확히 둡니다.

## 테스트 전략

테스트는 실제 프로세스를 종료하지 않습니다. 종료 흐름은 fake resolver와 fake terminator로 검증합니다. 서비스 상태 조회도 fake runner와 fake socket checker를 사용해 Docker/DB 상태, timeout, command path를 고정합니다.

주요 검증 영역:

- 포트 표현식 파싱과 기본 포트 프로파일 안정성
- 열린 포트만 메뉴 모델에 반영되는지 여부
- 모호한 listener가 종료 대상에서 제외되는지 여부
- 종료 직전 PID/process name mismatch 차단
- Docker daemon 상태 분류
- DB 기본 포트 상태 분류
- 서비스 조회 timeout 처리와 process reap
- 메뉴 컨트롤 항목과 읽기 전용 서비스 row 구성

## 공개 저장소 주의사항

이 저장소는 공개 상태로 둘 수 있도록 민감 정보를 코드에 넣지 않는 전제로 관리합니다.

- 로컬 agent 상태는 `.omo/`, `.omx/`를 ignore합니다.
- API key, token, password, private key는 커밋하지 않습니다.
- 개인 환경 전용 값이 필요하면 코드 상수가 아니라 로컬 설정이나 ignore된 파일을 사용합니다.
- 공개 문서에는 개인 계정, 내부 경로, 비공개 인프라 정보를 적지 않습니다.

## 아직 하지 않는 일

현재 범위를 명확히 하기 위해 다음 기능은 제공하지 않습니다.

- 백그라운드 서비스 자동 시작/종료
- Docker container 관리
- DB health check query 실행
- force kill
- 원격 호스트 포트 스캔
- 패키지 인스톨러 배포

## 라이선스

아직 라이선스 파일이 없습니다. 외부 사용을 명확히 허용하려면 별도의 `LICENSE`를 추가해야 합니다.
