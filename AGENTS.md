# AGENTS.md

## Project
- Name: `ptk`
- Goal: 로컬 개발 포트 감시/정리 도구 (Tauri GUI + Rust CLI)

## Structure
- `ui/`: Tauri 프론트엔드
- `src-tauri/`: Rust 백엔드 및 CLI(`port-watch-cli`)
- `docs/`: 프로젝트 문서

## Run Commands
- GUI dev: `npm run tauri dev`
- CLI scan: `cd src-tauri && cargo run --bin port-watch-cli -- scan --use-default`
- CLI watch: `cd src-tauri && cargo run --bin port-watch-cli -- watch --use-default --interval 3`

## Working Rules
- 변경은 최소 범위로 적용한다.
- 플랫폼별 동작(Windows/Linux)을 깨지 않도록 분기 코드를 유지한다.
- 포트 기본 프로파일 변경 시 `README.md`와 동기화한다.

## Commit Rules
- 커밋 규칙은 `docs/commit-rules.md`를 따른다.
- 핵심: Conventional Commits, 영어 prefix, 한국어 제목/본문, 50/72 규칙.
