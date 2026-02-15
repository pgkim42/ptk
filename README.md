# ptk

현재 버전: `v0.1` (`package/cargo semver: 0.1.0`)

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
  - 수동 즉시 스캔
  - 포트별 PID/프로세스명 표시
  - 확인 다이얼로그 후 프로세스 종료
- CLI
  - `scan`: 1회 조회
  - `watch`: 반복 감시
  - `--open-only`: 열린 포트만 출력
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
```

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
