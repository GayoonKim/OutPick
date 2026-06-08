# Dark Theme System Design

## 1. 핵심 문제

현재 OutPick은 라이트 모드를 강제하고, UIKit/SwiftUI 화면 곳곳에 `.white`, `.black`, `.gray`, `.systemBlue`, `.red`, 베이지 계열 색이 직접 지정되어 있다.

이번 작업의 목적은 앱을 다크 모드 전용으로 전환하고, 한 가지 형광 포인트 색상과 무채색 중심의 시각 시스템으로 재정렬하는 것이다.

이 작업은 단순 색상 치환이 아니라 아래 범위를 포함한다.

- 앱 전체 appearance 정책
- UIKit/SwiftUI 공통 색상 토큰
- 탭바, 네비게이션, 모달, 리스트, 카드, 입력창의 표면 위계
- 룩북 이미지 배경과 placeholder 정책
- 채팅 말풍선/상태 색 정책
- 접근성 대비 기준과 수동 QA 기준

## 2. 요구사항

- 앱은 시스템 설정과 무관하게 다크 모드만 지원한다.
- 브랜드 포인트 색상은 한 가지 형광색 계열로 둔다.
- 기본 UI는 무채색 스케일을 사용한다.
- 포인트 색상은 CTA, 선택 상태, 활성 tab, 주요 진행 상태처럼 사용자의 다음 행동을 안내하는 곳에 집중한다.
- 의미색은 예외로 허용한다.
  - 오류, 삭제, 차단, 신고, 위험 액션은 별도 destructive/error 색을 사용할 수 있다.
  - 성공/경고 색은 꼭 필요한 상태 피드백에만 제한적으로 사용한다.
- 채팅 말풍선은 포인트 색으로 채우지 않고 무채색 위계로 정리한다.
- 룩북 콘텐츠 이미지는 UI 장식보다 이미지 자체가 돋보이도록 처리한다.
- 접근성은 최소 WCAG AA 수준의 텍스트 대비를 목표로 한다.

## 3. 확정된 방향

### 3.1 다크 전용

선택:

- 앱 전체를 다크 appearance로 고정한다.
- `Info.plist`, `AppDelegate`, UIKit appearance, SwiftUI root 환경 중 실제 코드 구조에 맞는 최소 변경으로 라이트 모드 누수를 막는다.

이유:

- 사용자가 요청한 "다크 모드만 지원"과 가장 일치한다.
- 시스템 설정을 따르는 adaptive theme보다 화면별 검증 범위가 작아진다.
- 현재 라이트 강제 코드가 있어 다크 전용으로 전환할 기술 진입점이 명확하다.

### 3.2 포인트 색상 사용 범위

선택:

- 포인트 색상은 브랜드 액션과 현재 선택 상태에 집중한다.
- 정보 위계, 카드 배경, 채팅 말풍선, 일반 텍스트에는 포인트 색을 남발하지 않는다.

포인트 색 사용 후보:

- Primary CTA
- 활성 tab
- 선택된 segmented/tab 상태
- 링크성 액션
- 진행률, 로딩 중 핵심 indicator
- 활성 입력 cursor 또는 focus ring
- 좋아요 외의 일반 선택 highlight

포인트 색 사용 금지 또는 제한:

- 전체 화면 배경
- 대부분의 카드 배경
- 장문 텍스트
- 채팅 말풍선 전체 fill
- destructive 액션
- 오류/경고/성공 상태 전체

### 3.3 의미색 예외

선택:

- 좋아요, 삭제, 오류, 경고 같은 의미색은 포인트 색 하나로 억지 통합하지 않는다.
- 단, 색의 수와 채도는 제한한다.

이유:

- 삭제/오류를 포인트 색으로 바꾸면 위험 액션 인지가 약해진다.
- 좋아요 하트가 브랜드 포인트와 같아지면 "좋아요"와 "선택/CTA"의 의미가 섞일 수 있다.

## 4. 형광 포인트 색상 후보

확정:

- 최종 포인트 색상은 Volt Green `#7FDB1E`이다.

추천 후보:

| 이름 | HEX | 성격 | 장점 | 주의점 |
| --- | --- | --- | --- | --- |
| Volt Green | `#7FDB1E` | 라임과 그린 사이의 단단한 색 | 피로감이 낮고 버튼/탭에 안정적 | 형광 정체성은 조금 약해짐 |
| Signal Lime | `#8FEA00` | 형광 라임 감도는 유지하되 조금 더 어두움 | 다크 배경에서 충분히 보이고 `#B7FF2A`보다 덜 공격적 | Volt Green보다 조금 더 눈에 띌 수 있음 |
| Toxic Lime | `#9BEF1A` | 밝은 라임과 안정감 사이 | Electric Lime보다 덜 튀면서 형광감이 강함 | Signal Lime보다 밝아 이미지와 경쟁할 수 있음 |
| Dark Neon Lime | `#6FD400` | 가장 어두운 라임 후보 | 장시간 사용 피로도가 낮음 | 포인트로서의 즉시성이 약해질 수 있음 |
| Electric Lime | `#B7FF2A` | 선명하고 패션/스트리트 감도 높음 | 다크 배경에서 즉시 보임, OutPick에 개성 부여 | 현재 판단상 너무 밝아 기본 포인트로는 부담 가능 |
| Neon Cyan | `#22F3FF` | 미래적이고 깨끗함 | 다크 UI, 이미지 서비스와 잘 어울림 | iOS system blue와 인상이 겹칠 수 있음 |
| Hot Coral | `#FF4F7A` | 감정적이고 패션 친화적 | 좋아요/소셜 감성과 맞음 | destructive/error 색과 충돌 가능 |

추천안:

- 최종 선택: Volt Green `#7FDB1E`
- 대체 후보: Signal Lime `#8FEA00`
- 보류 후보: Electric Lime `#B7FF2A`

추천 이유:

- OutPick은 룩북/채팅/좋아요가 섞인 앱이므로 포인트 색은 콘텐츠 이미지와 경쟁하지 않으면서도 빠르게 눈에 들어와야 한다.
- Volt Green은 다크 무채색 UI에서 포인트로 충분히 보이면서도 Signal Lime보다 조금 더 어둡고 안정적이다.
- 형광 라임 계열의 개성은 유지하지만, 눈을 찌르는 느낌과 장시간 사용 피로도를 줄이는 쪽이다.
- Electric Lime은 초기 후보로는 강점이 있지만, 현재 사용자 피드백 기준으로는 너무 밝아 기본 포인트보다 특수 강조 후보에 가깝다.
- 단, 큰 면적 fill에는 쓰지 말고 작은 CTA, stroke, icon, selected state 중심으로 사용해야 한다.

## 5. 무채색 스케일

디자이너가 아니어도 일관되게 적용할 수 있도록 "색 이름"보다 "역할 이름"으로 관리한다.

### 5.1 권장 토큰

| Token | HEX | 역할 |
| --- | --- | --- |
| `backgroundBase` | `#090A0C` | 앱 최상위 배경 |
| `backgroundRaised` | `#101216` | 리스트, 큰 영역의 약한 표면 |
| `surfaceBase` | `#16191F` | 카드, 입력창, 탭바, sheet 표면 |
| `surfaceElevated` | `#1E222A` | 떠 있는 메뉴, bottom sheet, popover |
| `surfacePressed` | `#282D36` | pressed/highlight 상태 |
| `borderSubtle` | `#2A2F38` | 카드/구분선 기본 |
| `borderStrong` | `#3A414D` | 선택 전 stroke, 입력창 경계 |
| `textPrimary` | `#F4F6F8` | 제목/본문 핵심 텍스트 |
| `textSecondary` | `#AEB5C0` | 보조 설명, timestamp |
| `textTertiary` | `#747D8C` | placeholder, 비활성에 가까운 보조 텍스트 |
| `textDisabled` | `#505866` | disabled 텍스트 |
| `iconPrimary` | `#EEF1F5` | 주요 아이콘 |
| `iconSecondary` | `#8D96A6` | 보조 아이콘 |
| `overlayScrim` | `#000000` + 56% | 이미지 preview, modal dim |

### 5.2 설계 원칙

- 배경은 완전한 검정 `#000000` 대신 살짝 떠 있는 검정 `#090A0C`를 기본으로 한다.
  - 이유: 완전 검정은 이미지/카드/텍스트 경계를 너무 강하게 만들고 눈 피로를 키울 수 있다.
- 카드는 배경보다 1단계 밝은 `surfaceBase`를 사용한다.
- sheet, menu, popover는 카드보다 1단계 밝은 `surfaceElevated`를 사용한다.
- border는 그림자 대신 표면 구분을 담당한다.
- textPrimary와 backgroundBase의 대비는 충분히 높게 유지한다.
- textTertiary는 작은 글자에 남발하지 않는다.

### 5.3 피해야 할 패턴

- 비슷한 검정 10개를 화면마다 임의 생성하지 않는다.
- 포인트 색을 opacity로 낮춰 배경색처럼 쓰지 않는다.
- 흰색 텍스트를 모든 곳에 100%로 쓰지 않는다.
- 베이지/크림 계열 룩북 배경은 다크 시스템과 충돌하므로 제거하거나 토큰으로 대체한다.

## 6. 룩북 콘텐츠 이미지 배경 정책

룩북은 이미지가 핵심 콘텐츠이므로 다크 UI의 장식감보다 이미지 판독성이 우선이다.

### 옵션 A. Neutral Frame

설명:

- 이미지 카드 주변은 `surfaceBase`, 이미지 placeholder는 `backgroundRaised`를 사용한다.
- 이미지 자체에는 불필요한 tint/gradient를 올리지 않는다.
- 카드 경계는 `borderSubtle` 1px 또는 매우 약한 stroke로 구분한다.

장점:

- 이미지 색을 가장 정확하게 보여준다.
- 룩북/패션 콘텐츠와 잘 맞는다.
- 구현과 QA가 가장 안정적이다.

단점:

- 강한 브랜드 감도는 적다.

추천:

- 기본 카드, 브랜드/시즌/포스트 grid에 사용한다.

### 옵션 B. Soft Matte

설명:

- 이미지 로딩/빈 상태에 `surfaceBase`보다 약간 밝은 matte 배경을 깔고, 이미지가 로드되면 주변 여백만 남긴다.
- 이미지 비율이 맞지 않을 때 letterbox 영역을 `backgroundRaised`로 둔다.

장점:

- 서로 다른 비율의 이미지가 섞여도 화면이 안정적으로 보인다.
- 이미지가 없는 상태도 의도된 UI처럼 보인다.

단점:

- 이미지 주변 여백이 많으면 화면 밀도가 낮아질 수 있다.

추천:

- 브랜드 로고, 시즌 커버, 후보 이미지처럼 비율이 들쭉날쭉한 곳에 사용한다.

### 옵션 C. Focus Ring

설명:

- 선택된 이미지, 업로드 중 이미지, 실패 후 재시도 대상에만 포인트 색 stroke 또는 얇은 glow를 준다.
- 일반 이미지는 무채색 frame을 유지한다.

장점:

- 형광 포인트 색을 고급스럽게 제한적으로 쓸 수 있다.
- 선택 상태와 작업 상태가 명확하다.

단점:

- 포인트 stroke가 너무 두꺼우면 이미지와 경쟁한다.

추천:

- 선택 모드, import 후보 선택, 현재 활성 post, 업로드/재시도 상태에만 사용한다.

### 최종 추천 조합

- 기본은 옵션 A `Neutral Frame`.
- 비율이 다른 이미지/placeholder는 옵션 B `Soft Matte`.
- 선택/진행/재시도 상태에만 옵션 C `Focus Ring`.

## 7. 채팅 말풍선 정책

선택:

- 보낸 메시지와 받은 메시지 모두 무채색 표면 위계로 구분한다.
- 포인트 색은 전송 버튼, 현재 입력 focus, unread/highlight, 선택 상태에만 사용한다.

권장:

- 받은 메시지 bubble: `surfaceBase`
- 보낸 메시지 bubble: `surfaceElevated`
- 내 메시지 텍스트: `textPrimary`
- 상대 메시지 텍스트: `textPrimary`
- timestamp/read marker: `textTertiary`
- 답장 preview: `backgroundRaised` + `borderSubtle`
- 이미지/비디오 overlay: 기존 검정 overlay 유지 가능, 단 opacity만 토큰화한다.

이유:

- 채팅 화면은 반복 사용 시간이 길어서 형광색 말풍선은 피로도가 높다.
- 포인트 색은 "행동 가능성"과 "현재 상태"에 집중해야 한다.

## 8. 접근성 기준

목표:

- 일반 텍스트는 최소 WCAG AA 대비 4.5:1 이상을 목표로 한다.
- 큰 제목/아이콘성 큰 텍스트는 최소 3:1 이상을 목표로 한다.
- 포인트 색 위 흰색/검정 텍스트 조합은 실제 대비를 확인한 뒤 결정한다.

구현 전 검증 필요:

- Volt Green 같은 밝은 포인트 색 위에는 흰색보다 거의 검정에 가까운 텍스트가 더 안전할 가능성이 높다.
- Neon Cyan도 흰색 텍스트와 대비가 낮을 수 있으므로 CTA fill에 사용할 경우 `#090A0C` 텍스트를 우선 검토한다.

수동 QA 항목:

- 탭바 라벨 10pt 가독성
- 댓글 timestamp/metadata
- disabled 버튼과 enabled 버튼 구분
- 입력창 placeholder
- 이미지 위 overlay 버튼
- 오류/삭제 액션의 인지성
- 밝은 룩북 이미지와 어두운 룩북 이미지가 섞인 리스트

## 9. 코드 설계 방향

권장 구조:

- `OutPick/DesignSystem/OutPickTheme.swift`를 추가한다.
- UIKit과 SwiftUI에서 같은 역할 토큰을 사용할 수 있게 한다.
- 직접 색상 사용을 점진적으로 토큰으로 교체한다.

예상 역할:

- `OutPickColor` 또는 `OutPickTheme.Color`
  - UIKit: `UIColor`
  - SwiftUI: `Color`
- `OutPickAppearance`
  - window style
  - navigation bar appearance
  - tab bar/custom tab bar appearance
  - text input tint

주의:

- 레거시 UIKit 화면을 한 번에 구조 변경하지 않는다.
- 화면 이동, ViewModel, Repository, UseCase 경계는 변경하지 않는다.
- 이번 작업은 UI theme layer와 View 렌더링 색상에 집중한다.

## 10. 구현 전 남은 결정

확정:

- 최종 포인트 색상 HEX는 Volt Green `#7FDB1E`이다.

추천:

- Volt Green `#7FDB1E`로 진행한다.

확실하지 않음:

- 실제 기기 OLED 환경에서 Volt Green의 피로도는 수동 QA 전에는 확정할 수 없다.
- 일부 브랜드/시즌 이미지와 포인트 색이 충돌하는지는 실제 데이터로 확인해야 한다.
