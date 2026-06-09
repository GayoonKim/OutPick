# Dark Theme System Plan

## 목적

OutPick 다크 모드 전용 전환 작업의 phase 지도와 완료 기준 인덱스다.

상세 설계는 `design.md`, 결정 이유는 `decisions/theme-system.md`, 완료 기록은 `progress/completed.md`를 본다.

## Phase 지도

| Phase | 목표 | 상태 | 검증 |
| --- | --- | --- | --- |
| Phase 1 | 디자인 시스템 하네스 정리 | 완료 | 문서 검토 |
| Phase 2 | 공통 테마 토큰과 앱 appearance 전환 | 완료 | iOS build, root 화면 수동 확인 |
| Phase 3 | 탭바, 네비게이션, 공통 컴포넌트 정리 | 완료 | 탭/네비게이션/toast/loading 수동 QA |
| Phase 4A | 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트 적용 | 완료 | 룩북 홈/좋아요/이미지 상태 수동 QA, iOS build |
| Phase 4Nav | 룩북 SwiftUI 공통 네비게이션 바 적용 | 완료 | 홈/좋아요/상세 back/menu 수동 QA, iOS build |
| Phase 4B | 브랜드/시즌/포스트 상세 화면 적용 | 완료 | 상세 push, 이미지 밝기별 수동 QA |
| Phase 4C | 댓글, sheet, 생성/import 플로우 적용 | 완료 | 댓글/sheet/생성 플로우 수동 QA |
| Phase 5A | 채팅 탭 root/list/search 화면 적용 | 완료 | 목록/참여방/검색 수동 QA |
| Phase 5B | 채팅방 핵심 화면 적용 | 완료 | 채팅방/입력/첨부/검색/설정 수동 QA |
| Phase 5C | 방 생성/편집/설정/미디어 화면 적용 | 완료 | 생성/편집/설정/미디어 수동 QA |
| Phase 6 | 프로필, 마이페이지, 로그인/부트 적용 | 완료 | 로그인/프로필/마이페이지 수동 QA |
| Phase 7A | 최종 하드코딩 색상 sweep | 완료 | 색상 검색, iOS build |
| Phase 7B | 최종 앱 smoke QA | 완료 | 사용자 수동 QA |

## 주요 완료 기준

- 앱이 시스템 설정과 무관하게 다크로 표시된다.
- AccentColor가 Volt Green `#7FDB1E`로 설정된다.
- UIKit/SwiftUI 양쪽에서 역할 기반 색상 토큰을 사용한다.
- 공통 chrome, 룩북, 채팅, 로그인/프로필/마이페이지의 라이트 배경/검정 텍스트 누수를 제거한다.
- 포인트 색은 CTA, 선택, focus, 진행 상태 중심으로 제한한다.
- 좋아요, destructive, warning, success 같은 의미색은 semantic token으로 관리한다.
- media viewer 성격의 전체 화면 image/video preview는 black 배경 예외를 허용한다.
- 주요 화면 수동 QA와 iOS build가 통과한다.

## 테스트 설계

변경 유형:

- View 렌더링 변경.
- 앱 appearance 변경.
- 디자인 시스템 토큰 추가.

검증 우선순위:

- 색상 토큰 자체는 순수 계산 로직이 아니므로 unit test 우선순위는 낮다.
- 시각 완성도와 화면 감각은 실제 시뮬레이터/기기 수동 QA를 우선한다.
- 데이터/서버/상태 전이 로직 변경이 아니므로 fake repository 기반 테스트는 현재 범위에 필요하지 않다.

기본 검증:

- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build`
- phase별 대상 화면 수동 QA.
- 색상 직접 사용 검색.

## 상태

- 모든 구현 phase와 최종 smoke QA 완료.
- 다음 작업은 커밋 범위 정리다.
