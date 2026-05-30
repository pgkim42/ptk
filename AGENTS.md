# AGENTS.md

## Project
- Name: `ptk`
- Goal: 로컬 개발 포트 감시/정리 도구 (native Swift/AppKit macOS 메뉴 막대 앱)

## Structure
- `macos/`: Swift Package 기반 macOS 메뉴 막대 앱
  - `Sources/PTKApp/`: AppKit `NSStatusItem` 앱 진입점
  - `Sources/PTKCore/`: 포트 파싱, 스캔, 프로세스 조회, 종료 안전 로직
  - `Tests/PTKCoreTests/`: core 단위 테스트
- `docs/`: 프로젝트 문서

## Run Commands
- Swift app dev: `cd macos && swift run PTK`
- Swift test: `cd macos && swift test`
- Swift build: `cd macos && swift build`
- Xcode test: `cd macos && xcodebuild -scheme PTK -destination 'platform=macOS' test`

## Working Rules
- 변경은 최소 범위로 적용한다.
- Swift 앱 런타임에 Rust/Tauri/Node 의존성을 추가하지 않는다.
- 포트 기본 프로파일 변경 시 `README.md`, `macos/Sources/PTKCore/Domain/AppDefaults.swift`, 관련 테스트를 동기화한다.
- 프로세스 종료 관련 변경은 확인, 재검증, mismatch 차단, `SIGTERM` only 정책을 깨지 않도록 테스트로 고정한다.

## Commit Rules
- 커밋 규칙은 `docs/commit-rules.md`를 따른다.
- 핵심: Conventional Commits, 영어 prefix, 한국어 제목/본문, 50/72 규칙.
