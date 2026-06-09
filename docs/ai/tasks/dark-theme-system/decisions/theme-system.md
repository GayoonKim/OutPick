# Dark Theme System Decision Details

## D-001: 앱은 다크 모드 전용으로 전환한다

상태: accepted.

선택:

- 시스템 라이트/다크 설정을 따르지 않고 앱 전체를 다크 appearance로 고정한다.

이유:

- 사용자가 "다크 모드만 지원"을 요청했다.
- 기존 앱은 라이트 모드를 강제하고 있어 전역 appearance 전환 지점이 명확하다.
- adaptive theme보다 검증해야 할 화면 상태가 줄어든다.

트레이드오프:

- 사용자가 시스템 라이트 모드를 사용해도 앱은 다크로 표시된다.

## D-002: 브랜드 포인트 색은 Volt Green 한 가지로 제한한다

상태: accepted.

선택:

- 포인트 색은 Volt Green `#7FDB1E` 한 가지로 둔다.
- CTA, 선택 상태, 활성 tab, focus, 진행 상태에 집중적으로 사용한다.

후보:

- 최종 선택: Volt Green `#7FDB1E`
- 대체 후보: Signal Lime `#8FEA00`
- 보류 후보: Electric Lime `#B7FF2A`

이유:

- Electric Lime `#B7FF2A`는 너무 밝게 느껴질 수 있다.
- Volt Green은 작은 면적에서는 충분히 눈에 들어오고, 룩북 이미지와의 경쟁이 낮을 가능성이 높다.

트레이드오프:

- 형광색은 브랜드 기억점이 강하지만 넓은 면적에 쓰면 피로도가 높아진다.

## D-003: 의미색은 포인트 색 예외로 허용한다

상태: accepted.

선택:

- 오류, 삭제, 차단, 신고, 위험 액션은 destructive/error 색을 별도로 사용할 수 있다.
- 좋아요 색도 포인트 색과 반드시 통합하지 않는다.

이유:

- 위험/오류 상태를 포인트 색으로 통합하면 사용자가 의미를 오해할 수 있다.
- 포인트 색은 브랜드/행동 유도 역할에 집중하는 편이 명확하다.

## D-004: 무채색은 역할 기반 토큰으로 정의한다

상태: accepted.

선택:

- `backgroundBase`, `surfaceBase`, `surfaceElevated`, `borderSubtle`, `textPrimary`처럼 역할 기반 이름을 사용한다.
- 화면마다 임의 HEX를 만들지 않는다.

이유:

- 디자이너가 아닌 개발자도 일관되게 적용할 수 있다.
- UIKit/SwiftUI가 섞인 앱에서 색상 의도를 공유하기 쉽다.

## D-005: 룩북 이미지는 Neutral Frame 중심으로 처리한다

상태: accepted.

선택:

- 기본 이미지는 무채색 frame 위에 그대로 표시한다.
- 비율이 맞지 않거나 placeholder가 필요한 이미지는 Soft Matte 배경을 사용한다.
- 선택/진행/재시도 상태에만 포인트 색 focus ring을 사용한다.

이유:

- 룩북은 이미지가 핵심 콘텐츠이므로 UI 색이 이미지와 경쟁하면 안 된다.

## D-006: 채팅 말풍선은 무채색 위계로 정리한다

상태: accepted.

선택:

- 보낸 메시지와 받은 메시지는 서로 다른 무채색 surface로 구분한다.
- 포인트 색은 전송 버튼, focus, unread/highlight, 선택 상태에만 사용한다.

이유:

- 형광 말풍선은 반복 사용에서 피로도가 높다.
- 채팅의 핵심은 메시지 가독성이므로 텍스트 대비와 표면 위계가 우선이다.

## D-007: 접근성은 최소 WCAG AA 수준을 목표로 한다

상태: accepted.

선택:

- 일반 텍스트 대비는 4.5:1 이상을 목표로 한다.
- 작은 보조 텍스트와 disabled 상태는 실제 화면에서 식별 가능성을 확인한다.
- 포인트 색 위 텍스트는 실제 대비 계산 후 흰색/검정 계열을 결정한다.

이유:

- 다크 UI는 작은 회색 텍스트가 쉽게 묻힌다.

## D-008: Phase 4 룩북 화면군은 4A/4B/4C로 나눈다

상태: accepted.

선택:

- Phase 4A: 룩북 홈, 좋아요 탭, 공통 이미지 컴포넌트.
- Phase 4B: 브랜드 상세, 시즌 상세, 포스트 상세.
- Phase 4C: 댓글/대댓글, 신고/삭제/차단 sheet, 브랜드/시즌 생성 플로우.

이유:

- 룩북 화면군은 이미지 카드, 상세 화면, 댓글 sheet, 생성 플로우가 모두 섞여 있어 한 번에 바꾸면 QA 범위가 지나치게 커진다.

## D-009: 의미색도 테마 토큰으로 관리한다

상태: accepted.

선택:

- `OutPickTheme`에 `like`, `destructive`, `warning`, `success` 의미색 토큰을 추가한다.

이유:

- 의미색은 포인트 색 예외지만, 예외도 앱 전체에서 일관되어야 한다.

## D-010: 전체 화면 이미지 preview의 검정 배경은 의도된 예외로 둔다

상태: accepted.

선택:

- `PostImagePreviewView`처럼 media viewer 성격이 강한 전체 화면 이미지 preview는 순수 black 배경을 허용한다.

이유:

- 이미지 감상 화면은 앱 surface보다 라이트박스에 가깝다.

트레이드오프:

- 색상 검색에서 `Color.black`이 남을 수 있다.
- 이를 의도된 media viewer 예외로 기록하고 일반 화면 배경과 구분한다.

## D-011: 룩북 생성 플로우의 베이지/크림 계열은 제거한다

상태: accepted.

선택:

- 브랜드/시즌 생성 플로우의 베이지/크림 계열 배경은 다크 무채색 토큰으로 대체한다.
- 별도 warm dark matte 토큰은 현재 만들지 않는다.

이유:

- 현재 목표는 한 가지 포인트 색상과 무채색 조합이다.

## D-012: 상호작용 가능한 일반 버튼은 포인트 색을 기본으로 사용한다

상태: accepted.

선택:

- tappable icon/button, 일반 navigation action, 이미지 추가/첨부/검색/설정처럼 상호작용 가능한 기본 액션은 Volt Green accent를 사용한다.
- 삭제, 신고, 차단, 실패, 위험 액션은 destructive/error semantic token을 우선한다.
- 좋아요처럼 별도 의미가 강한 액션은 like semantic token을 유지한다.
- 넓은 면적의 버튼 fill은 필요한 primary CTA에 제한하고, 보조 버튼은 accent icon/text 또는 낮은 alpha accent background를 사용한다.

이유:

- 상호작용 가능한 요소가 중립색이면 버튼성이 약하게 보일 수 있다.
- 다크 화면에서 accent가 action affordance 역할을 안정적으로 한다.
