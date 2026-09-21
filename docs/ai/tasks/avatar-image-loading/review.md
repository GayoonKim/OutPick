# 아바타 이미지 로딩 PR 리뷰

대상: [PR #32](https://github.com/GayoonKim/OutPick/pull/32), 2026-09-21. 작성 에이전트의 자체 리뷰이며 독립 외부 승인과 구분한다.

## 발견 사항과 수정

- P2: SwiftUI 댓글의 행 ID/좌표가 그대로인 상태에서 사진 경로만 바뀌면 `AvatarViewportObserver`의 변경 콜백이 이전 items로 선로딩을 계산했다. 실제 UIHostingController/ScrollView와 spy를 사용해 nil→첫 사진→변경 사진 요청 누락을 재현했다. `onChange`의 최신 배열을 `update(items:)`에 직접 전달하도록 수정했다. 화면의 실제 표시 요청과 별개인 선로딩 경로의 문제다.
- 정리: 전송 실패 아이콘에 불필요하게 적용된 `AvatarImageView`를 기존 `UIImageView`로 복원했다. 아이콘에 아바타 상태 객체를 만들지 않는다.

## 검증

- 수정 전: `AvatarNestedViewportTests`의 기존 중첩 참여자 검증은 통과, 새 SwiftUI 경로 갱신 테스트는 첫 사진·변경 사진 모두 실패했다. 로그 `/private/tmp/outpick-avatar-pr-review-tests.log`.
- 수정 후: Simulator 빌드 및 XCTest 2개(중첩 참여자·SwiftUI 경로 갱신), Swift Testing 18개(viewport·표시 수명) 모두 통과했다. 로그 `/private/tmp/outpick-avatar-pr-review-fixed-tests.log`, xcresult `Test-OutPick-Development-2026.09.21_15-41-32-+0900.xcresult`. 이번 보완을 실기기에 재설치하거나 수동 QA를 반복하지는 않았다.
- 기존 광범위 112개 및 후속 실기기 16개 결과는 [Phase5](progress/phase-5.md) 참조. 중복 실행을 합산하지 않는다.

## 검토 범위와 한계

- 위 보완 후 검토 범위에서 머지를 막을 추가 결함은 발견하지 못했다.

- 공용 pipeline의 transient/저장 승격, 세션·사진 무효화, 표시 수명·재시도, 사용처별 DI 정책, UIKit/SwiftUI viewport, 원본 viewer 정리와 변경 테스트를 검토했다.
- 임시 QA 코드·자료 제거 기록과 커밋 범위를 대조했다. 서버 배포/규칙 변경은 없다. HANDOFF·개인 포트폴리오·로컬 로그는 PR에서 제외했다.
- VoiceOver는 사용자 합의로 제외한다. 상위 화면 이동 전체의 자동화와 실제 서버 성능 계측으로 확대 해석하지 않는다.
- GitHub 조회 시 main 보호는 활성화되어 있으며 필수 CI 검사 및 필수 승인 수는 0이었다. 자체 리뷰 기록과 로컬 검증 후 일반 머지를 사용하며 보호 규칙을 우회하지 않는다.
