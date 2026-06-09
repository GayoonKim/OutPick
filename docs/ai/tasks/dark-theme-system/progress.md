# Dark Theme System Progress

## 목적

다크 테마 시스템 작업의 현재 상태와 상세 진행 기록의 읽는 순서를 제공하는 인덱스다.

## 읽는 순서

- 현재 상태와 다음 작업: 이 문서.
- 상세 완료 기록: `progress/completed.md`.
- phase 지도와 완료 기준: `plan.md`.
- 색상/화면/정책 설계: `design.md`.
- 결정 이유와 보류한 대안: `decisions.md`, `decisions/theme-system.md`, `../../ADR.md`의 ADR-010.
- active task 포인터: `HANDOFF.md`, `../active.md`.

## 현재 상태

- 작업명: `dark-theme-system`.
- 최종 목표: OutPick을 다크 모드 전용 앱으로 전환하고, Volt Green `#7FDB1E` 포인트 색상과 무채색 스케일을 중심으로 UIKit/SwiftUI 화면의 시각 시스템을 정리한다.
- 구현 상태: Phase 1...7B 완료.
- 사용자 수동 QA: 완료.
- 다음 작업: 다크 모드 변경 범위를 커밋 단위로 정리한다.

## 완료 요약

- Phase 1: 디자인 시스템 하네스 정리.
- Phase 2: 공통 테마 토큰과 앱 appearance 전환.
- Phase 3: 탭바, 네비게이션, 공통 컴포넌트 정리.
- Phase 4A: 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트 적용.
- Phase 4Nav: 룩북 SwiftUI 공통 네비게이션 바 적용.
- Phase 4B: 브랜드/시즌/포스트 상세 화면 적용.
- Phase 4C: 댓글, sheet, 생성/import 플로우 적용.
- Phase 5A: 채팅 탭 root/list/search 화면 적용.
- Phase 5B: 채팅방 핵심 화면 적용.
- Phase 5C: 방 생성/편집/설정/미디어 화면 적용.
- Phase 6: 프로필, 마이페이지, 로그인/부트 적용.
- Phase 7A: 최종 하드코딩 색상 sweep.
- Phase 7B: 최종 앱 smoke QA.

## 검증 상태

- `jq empty OutPick/Assets.xcassets/AccentColor.colorset/Contents.json` 통과.
- `plutil -lint OutPick/Info.plist` 통과.
- `xcodebuild -scheme OutPick -destination 'generic/platform=iOS Simulator' build` 통과.
- `git diff --check` 통과.
- phase별 색상 직접 사용 검색과 사용자 수동 QA 완료.

상세 검증 기록과 변경 파일 인덱스는 `progress/completed.md`를 본다.

## 남은 작업

- Git 추적 상태와 커밋 범위 정리.
- `OutPick/App/AppDelegate.swift`, `OutPick/Info.plist`, `HANDOFF.md`, `docs/ai/tasks/*`는 ignore/exclude 대상일 수 있으므로 커밋 시 포함 여부를 재확인한다.

## 불확실한 부분

- 추측입니다: 형광 포인트 색은 룩북/패션 맥락에서 브랜드 기억점을 만들 가능성이 높다. 다만 과도하게 쓰면 앱이 가벼워 보일 수 있어 사용 범위를 좁게 유지해야 한다.
