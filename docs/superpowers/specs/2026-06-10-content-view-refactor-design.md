# ContentView 구조 분리 설계

## 목표

`ContentView.swift`에 모여 있는 메뉴 바 패널 UI 조립 코드를 작은 뷰
단위로 분리한다. Swift를 깊게 모르는 사람도 파일 이름만 보고 화면
구조를 파악할 수 있게 만드는 것이 이번 리팩터링의 목적이다.

## 범위

- `ContentView.swift`는 전체 패널의 상위 배치와 시트, 확인 대화상자
  연결을 맡는다.
- 반복적으로 독립된 화면 영역은 별도 SwiftUI 뷰 파일로 분리한다.
- 포트 스캔, 프로세스 조회, 종료 안전 로직, 서비스 상태 조회 방식은
  변경하지 않는다.
- 사용자에게 보이는 문구와 동작은 그대로 유지한다.

## 분리 대상

- `PortSummaryHeaderView`: 상단 열린 포트 요약과 새로고침 버튼
- `RecentPortChangesView`: 최근 포트 변화 목록
- `OpenPortsSectionView`: 열린 포트 목록과 빈 상태
- `ServiceStatusSectionView`: Docker, DB, 사용자 서비스 상태 목록
- `PanelFooterView`: 프로필 전환, 갱신 주기, 복사, 설정, 종료 버튼

분리 후에도 기존 `PortRowView`, `ServiceStatusRowView`,
`DockerContainerPortRowView`, `SettingsSheetView`는 그대로 재사용한다.

## 데이터 흐름

새 뷰들은 `PortMonitorViewModel`을 직접 받거나 필요한 값과 동작만
전달받는다. 첫 구현에서는 변경 범위를 줄이기 위해 `ContentView`와
같은 방식으로 `PortMonitorViewModel`을 공유하고, 불필요한 모델 변경은
하지 않는다.

## 오류 처리와 안전 정책

이번 변경은 UI 파일 분리만 수행한다. 다음 정책은 그대로 유지한다.

- 종료 전 확인
- 종료 직전 재검증
- PID 또는 프로세스 이름 mismatch 차단
- ambiguous listener 차단
- `SIGTERM` only

## 테스트와 검증

구현 후 다음 명령으로 기존 동작이 유지되는지 확인한다.

```sh
cd macos && swift test
```

구조 변경이 UI 조립에 머물렀는지 확인하기 위해 최종 diff에서
`PTKCore/Features/PortMonitor/Services/ProcessKiller.swift`와 종료
안전 테스트가 불필요하게 바뀌지 않았는지도 확인한다.
