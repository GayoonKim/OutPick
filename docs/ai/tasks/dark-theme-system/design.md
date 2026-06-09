# Dark Theme System Design

## 목적

OutPick을 다크 모드 전용 앱으로 전환하고, Volt Green `#7FDB1E` 포인트 색상과 무채색 스케일을 중심으로 UIKit/SwiftUI 화면의 시각 시스템을 정리한다.

상세 결정 이유와 대안은 `decisions/theme-system.md`, 실제 진행/검증 기록은 `progress/completed.md`를 본다.

## 핵심 문제

기존 앱은 라이트 모드를 강제하고, UIKit/SwiftUI 화면 곳곳에 `.white`, `.black`, `.gray`, `.systemBlue`, `.red`, 베이지 계열 색이 직접 지정되어 있었다.

이번 작업은 단순 색상 치환이 아니라 앱 전체 appearance, 공통 색상 토큰, 탭바/네비게이션/모달/리스트/카드/입력창 표면 위계, 룩북 이미지 배경, 채팅 말풍선, 접근성 대비 기준을 함께 정리하는 작업이다.

## 확정 요구사항

- 앱은 시스템 설정과 무관하게 다크 모드만 지원한다.
- 브랜드 포인트 색상은 Volt Green `#7FDB1E` 한 가지로 둔다.
- 기본 UI는 무채색 스케일을 사용한다.
- 포인트 색상은 CTA, 선택 상태, 활성 tab, focus, 진행 상태처럼 사용자의 다음 행동을 안내하는 곳에 집중한다.
- 오류, 삭제, 차단, 신고, 위험 액션, 좋아요 같은 의미색은 포인트 색 예외로 허용한다.
- 채팅 말풍선은 포인트 색으로 채우지 않고 무채색 위계로 정리한다.
- 룩북 콘텐츠 이미지는 UI 장식보다 이미지 자체가 돋보이도록 처리한다.
- 접근성은 최소 WCAG AA 수준의 텍스트 대비를 목표로 한다.

## 색상 정책

포인트 색상:

- 최종 선택: Volt Green `#7FDB1E`
- 대체 후보였던 색: Signal Lime `#8FEA00`
- 보류 후보였던 색: Electric Lime `#B7FF2A`

Volt Green은 다크 무채색 UI에서 포인트로 충분히 보이면서도 너무 밝은 형광 라임보다 피로도가 낮다. 큰 면적 fill에는 제한하고 작은 CTA, stroke, icon, selected state 중심으로 사용한다.

무채색 토큰:

| Token | HEX | 역할 |
| --- | --- | --- |
| `backgroundBase` | `#090A0C` | 앱 최상위 배경 |
| `backgroundRaised` | `#101216` | 리스트, 큰 영역의 약한 표면 |
| `surfaceBase` | `#16191F` | 카드, 입력창, 탭바, sheet 표면 |
| `surfaceElevated` | `#1E222A` | 메뉴, bottom sheet, popover |
| `surfacePressed` | `#282D36` | pressed/highlight 상태 |
| `borderSubtle` | `#2A2F38` | 카드/구분선 기본 |
| `borderStrong` | `#3A414D` | 선택 전 stroke, 입력창 경계 |
| `textPrimary` | `#F4F6F8` | 제목/본문 핵심 텍스트 |
| `textSecondary` | `#AEB5C0` | 보조 설명, timestamp |
| `textTertiary` | `#747D8C` | placeholder, 보조 텍스트 |
| `textDisabled` | `#505866` | disabled 텍스트 |
| `iconPrimary` | `#EEF1F5` | 주요 아이콘 |
| `iconSecondary` | `#8D96A6` | 보조 아이콘 |
| `overlayScrim` | `#000000` + 56% | modal dim, media overlay |

피해야 할 패턴:

- 비슷한 검정 HEX를 화면마다 임의 생성하지 않는다.
- 포인트 색을 opacity로 낮춰 배경색처럼 쓰지 않는다.
- 흰색 텍스트를 모든 곳에 100%로 쓰지 않는다.
- 베이지/크림 계열 룩북 배경은 다크 토큰으로 대체한다.

## 룩북 이미지 정책

기본 조합:

- 기본 카드, 브랜드/시즌/포스트 grid: Neutral Frame.
- 비율이 다른 이미지, 로딩, 빈 상태, 후보 이미지: Soft Matte.
- 선택, import 후보, 업로드/재시도 상태: Focus Ring.

정책:

- 이미지 자체에는 불필요한 tint/gradient를 올리지 않는다.
- 일반 이미지는 무채색 frame을 유지한다.
- 선택/진행/재시도 상태에만 포인트 색 stroke 또는 얇은 강조를 사용한다.
- 전체 화면 이미지 preview의 순수 black 배경은 media viewer 예외로 허용한다.

## 채팅 정책

- 보낸 메시지와 받은 메시지는 서로 다른 무채색 surface로 구분한다.
- 포인트 색은 전송 버튼, 현재 입력 focus, unread/highlight, 선택 상태에만 사용한다.
- 받은 메시지 bubble은 `surfaceBase`, 보낸 메시지 bubble은 `surfaceElevated`를 기본으로 둔다.
- timestamp/read marker는 `textTertiary`를 사용한다.
- 이미지/비디오 overlay는 기존 의미를 유지하되 토큰화한다.

## 접근성 기준

- 일반 텍스트는 최소 WCAG AA 대비 4.5:1 이상을 목표로 한다.
- 큰 제목/아이콘성 큰 텍스트는 최소 3:1 이상을 목표로 한다.
- Volt Green 같은 밝은 포인트 색 위 텍스트는 거의 검정에 가까운 텍스트를 우선 검토한다.
- 탭바 라벨, 댓글 timestamp, disabled 버튼, 입력창 placeholder, 이미지 위 overlay 버튼, 오류/삭제 액션은 수동 QA 대상으로 둔다.

## 코드 설계 방향

- `OutPick/DesignSystem/OutPickTheme.swift`를 기준 테마 파일로 둔다.
- UIKit과 SwiftUI에서 같은 역할 토큰을 사용할 수 있게 한다.
- `OutPickAppearance`는 window style, navigation bar appearance, tab bar appearance, text input tint 같은 전역 appearance를 담당한다.
- 레거시 UIKit 화면의 화면 이동, ViewModel, Repository, UseCase 경계는 변경하지 않는다.
- 이번 작업은 UI theme layer와 View 렌더링 색상에 집중한다.

## 상태

- 다크 모드 시스템 구현과 수동 QA는 완료됐다.
- 남은 작업은 커밋 범위 정리뿐이다.
- 확실하지 않음: 실제 기기 OLED 환경에서 Volt Green의 장시간 피로도는 수동 QA 범위 밖이다.
