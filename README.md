# ptk

현재 버전: `v0.4-swift-migration` (Swift macOS menu-bar migration target)

로컬 개발 중 남겨진 포트(예: `3000`, `8080`)를 감시하고, 점유 프로세스를 확인/종료하는 macOS 메뉴 막대 도구입니다.

## Swift 마이그레이션 대상

- 마이그레이션 대상: `macos/`의 native Swift macOS 앱
- UI 셸: AppKit `NSStatusItem` 메뉴 막대 앱
- 배포 대상: macOS 13+
- 런타임 경계: Swift 앱은 Rust/Tauri 코어를 호출하거나 embed하지 않습니다.
- 기존 `ui/`, `src-tauri/`, `port-watch-cli`는 Swift parity 검증 전까지 남겨둔 legacy/reference 구현입니다.

## 기본 포트 프로파일

Swift 앱의 기본 감시 포트는 기존 문서/레거시 상수와 동일합니다.

- `3000-3009` (Next.js 계열)
- `5173-5182` (Vite 계열)
- `4200-4209` (Angular 계열)
- `8080-8089` (Spring Boot 계열)

표현식: `3000-3009,5173-5182,4200-4209,8080-8089`

## Swift 메뉴 막대 기능

- 메뉴 막대 제목에 열린 감시 포트 수 표시
- 열린 감시 포트 목록 표시
- 포트별 PID/프로세스명 표시(조회 가능할 때)
- 수동 새로고침
- 새로고침 주기 프리셋(`1s`, `3s`, `5s`, `10s`) 및 `UserDefaults` 저장
- 종료 전 native 확인 알림
- 확인 후 포트/PID/프로세스명을 즉시 재조회하고, 불일치나 조회 실패 시 종료 차단
- 첫 Swift parity에서는 soft 종료(`SIGTERM`)만 사용하며 force kill과 mismatch override는 제공하지 않습니다.

## Swift 개발 실행

사전 준비:
- Xcode 26.5+ 또는 Swift 6.3+ toolchain
- macOS 개발 환경

검증:

```bash
cd macos && swift test
cd macos && swift build
cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test
```

실행(개발용):

```bash
cd macos && swift run PTK
```

## 레거시 / reference 구현

아래 명령은 Swift 앱 parity 검증이 끝날 때까지 동작 비교와 회귀 참고용으로만 유지합니다. 새 기능은 `macos/` Swift 앱에 우선 구현합니다.

### Legacy Tauri GUI

```bash
npm install
npm run tauri dev
```

### Legacy Rust CLI 예시

```bash
cd src-tauri
cargo run --bin port-watch-cli -- scan --use-default
cargo run --bin port-watch-cli -- watch --use-default --interval 3
cargo run --bin port-watch-cli -- watch --use-default --interval 3 --open-only
cargo run --bin port-watch-cli -- scan --ports "3000-3009,8080-8089" --json
cargo run --bin port-watch-cli -- scan --use-default --open-only --json
cargo run --bin port-watch-cli -- kill --pid 12345 --yes
cargo run --bin port-watch-cli -- kill --pid 12345 --yes --force
cargo run --bin port-watch-cli -- kill --pid 12345 --yes --expect-name node
cargo run --bin port-watch-cli -- kill --pid 12345 --yes --expect-name node --allow-mismatch
```

### Legacy kill 정책 참고

- GUI: `pid + process_name` 검증 실패 시 종료 차단
- CLI: `--expect-name` 미지정 시 호환 모드로 동작(경고 출력 후 PID 단독 종료)
- CLI `--allow-mismatch`: 불일치/조회 실패 시 경고 후 강행 종료

Swift 앱은 위 legacy 강행 정책을 첫 parity에 포함하지 않습니다.

## old-stack 삭제 게이트

`ui/`, `src-tauri/`, Node/Tauri packaging, Windows/Linux 빌드 문서는 Swift 메뉴 막대 core parity 증거가 기록된 뒤 별도 cleanup에서 삭제합니다. 삭제 전 최소 조건:

- Swift 앱 build/test 통과
- 기본 포트가 README와 Swift 상수에서 동일
- 메뉴 막대 count/list/PID/process/refresh/interval/kill-confirmation/revalidation 동작 검증
- `.omx/evidence/` 또는 ultragoal checkpoint에 parity 증거 기록
- 기존 Tauri/CLI가 supported product path가 아니라 legacy/reference임이 문서화됨
