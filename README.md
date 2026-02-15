# ptk

현재 버전: `v0.3` (`package/cargo semver: 0.3.0`)

로컬 개발 중 남겨진 포트(예: `3000`, `8080`)를 감시하고, 점유 프로세스를 확인/종료하는 도구입니다.

## 기본 포트 프로파일

- `3000-3009` (Next.js 계열)
- `5173-5182` (Vite 계열)
- `4200-4209` (Angular 계열)
- `8080-8089` (Spring Boot 계열)

## 기능

- GUI(Tauri)
  - 기본 포트 자동 로드
  - 3초 주기 자동 감시(기본 ON)
  - 열린 포트만 표시(기본 ON, 토글 가능)
  - 잘못된 포트 입력 시 즉시 오류 표시(strict parsing)
  - 수동 즉시 스캔
  - 포트별 PID/프로세스명 표시
  - 확인 다이얼로그 후 프로세스 종료
  - 프로세스명 불일치/조회 실패 시 기본 종료 차단
  - `정보 불일치 시 강행` 옵션으로만 강행 종료 허용
- CLI
  - `scan`: 1회 조회
  - `watch`: 반복 감시
  - `--open-only`: 열린 포트만 출력
  - `kill --force`: 강제 종료(기본은 soft 종료)
  - `kill --expect-name`: 프로세스명 검증 후 종료
  - `kill --allow-mismatch`: 불일치/조회 실패 시 경고 후 강행 종료
  - 테이블 형태 출력 + `OPEN/CLOSED` 색상 표시
  - `DETAIL` 메시지 한국어 표시(예: `연결 거부됨`)
  - `kill`: PID 종료

## 개발 실행

사전 준비:
- Node.js 18+
- Rust (`rustup`)

```bash
npm install
npm run tauri dev
```

## CLI 실행 예시

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

## kill 안전 정책 및 종료코드

- 기본 정책
  - GUI: `pid + process_name` 검증 실패 시 종료 차단
  - CLI: `--expect-name` 미지정 시 호환 모드로 동작(경고 출력 후 PID 단독 종료)
- 강행 정책
  - GUI: `정보 불일치 시 강행` 체크 시에만 강행 종료 허용
  - CLI: `--allow-mismatch` 지정 시에만 불일치/조회 실패 강행 허용
- 참고: 검증은 오인 종료 위험을 줄이기 위한 장치이며, PID 재사용 경합(TOCTOU)을 완전히 제거하지는 않습니다.

CLI `kill` 종료코드:
- `0`: 종료 성공
- `1`: OS 명령 실패/권한 문제
- `2`: 인자 오류(`--yes` 누락, 잘못된 pid 등)
- `3`: 안전검증 차단(프로세스명 불일치/조회 실패)

## Windows 빌드 (exe 우선)

사전 준비:
- Rust (MSVC toolchain)
- Node.js 18+
- Visual Studio C++ Build Tools
- WebView2 Runtime

GUI exe:

```bash
npm install
npm run tauri build
```

CLI exe:

```bash
cd src-tauri
cargo build --release --bin port-watch-cli
```

산출물 예시:
- GUI 번들: `src-tauri/target/release/bundle/`
- CLI exe: `src-tauri/target/release/port-watch-cli.exe`
