# 아바타 이미지 로딩 현재 상태

> **2026-09-21 PR #32 리뷰 보완:** 작업별 앱·테스트·문서 커밋 후 PR 생성. SwiftUI 경로만 변경할 때 선로딩 누락을 재현하고 최신 콜백 값 전달로 수정했다. 전송 실패 아이콘의 불필요한 아바타 타입도 복원했다. 수정 후 Simulator 빌드와 관련 20개 회귀 통과. [리뷰 결과·검증 한계](review.md). 아래 최종 QA 기록 이후의 추가 수정이며 현재 PR 머지 진행 중이다.

> **2026-09-21 Phase0~5 완료:** 잔여4개 QA를 DI코드대조·실제UIKit/spies·서비스pipeline·iPhone14 실행으로검증. 기존회귀112개와별도기기16개통과(중복합산안함). VoiceOver사용자제외, QA서버/기기/로컬임시자료·진단코드정리완료. 일반DEV build/install/launch·main tab확인(`/private/tmp/outpick-avatar-qa-complete-{build,install,console}.log`). 이번추가변경은테스트3파일과하네스이며제품코드수정없음. [최종증거·한계](progress/phase-5.md), [체크리스트](qa-checklist.md). 다음핵심작업은채팅방대표이미지설계이며미착수. 아래미완료/대기문구는과거이력이다.

> **2026-09-20 후속 QA 최신:** 내 사진 변경·제거·원복/닉네임 변경·원복, 로그아웃 디스크4→0/대기0 및 동일계정 재로그인 정상 확인. 원본 확대 오프라인장기대기를30초 제한으로 보완, 자동19+10개 통과/실기기30.72초취소·온라인retry1.09초성공. 마지막QA8문서2이미지 및 기기1행1이미지/임시자료정리, 정상DEV복구완료. 미검증 세부항목은 qa-checklist 유지하며 Phase5전체완료 선언 전 최종 대조 필요.

> **2026-09-20 최신:** 댓글·답글·참여자 화면 QA 통과. 댓글 상단 미표시/초고속 깜빡임 수정 후 사용자 정상 확인, 답글 large 확장 및 설정 초기상단/하단액션 스크롤 검증 완료. 즉시 메모리 표시 회귀46개 통과. QA 서버377문서/120이미지·기기50행/50이미지·Firestore 캐시·생성 파일 정리 완료, 정상 DEV 복구/메인 탭 확인. Phase5 전체 완료는 아니며 내 프로필 변경/네트워크/로그아웃 등 미검증 수동 항목 유지. [최신 결과](progress/phase-5.md).

> 2026-09-19 정리 완료: 승인된 미전송 쓰기 반영 확인→DEV Firestore 캐시 초기화, QA 로컬24행/이미지12개 삭제, 서버190문서/24이미지와 파생 자료 잔여0. 임시 Swift 코드 제거·정상 DEV 빌드/설치/메인 탭 로그 확인. 생성 이미지·원장·스크립트 삭제 완료. Phase5는 채팅 스크롤/확대 반복 정상 및 CPU/메모리 계측 완료, 다른 화면 수동QA·프레임은 미완료.

> 2026-09-19 최신: 채팅 빠른 스크롤·확대 반복 사용자 이상 없음, 두 번째 표본 CPU 최대51.5%/메모리 최대77.3→대기62.1MiB. QA 서버190문서·24이미지 삭제 및 잔여0 확인. 기기 캐시/임시 파일 정리 진행 중이며 Firestore 전체 캐시 초기화 범위 사용자 선택 대기. 다른 화면 수동 QA/프레임 계측은 미완료. [결과·정리 상태](progress/phase-5.md).

> 2026-09-18 Phase5 진행 승인: 통합 회귀·실기기 빌드 준비 시작, iPhone14와 DEV 설치 확인. 대표 QA 자료는 사용자 확인 중. [실시간 검증 기록](progress/phase-5.md). 실기기 QA 및 최종 완료는 아직 미확정이다.

> 2026-09-18 최신: **Phase4 구현·자동 검증 완료**. UIKit/SwiftUI viewport1.5/0.5·고유24경로·이탈300ms, 새 표시/메시지/참여 계기 재시도, 세션 unavailable 차단·수동 해제 구현. 통합 Swift Testing59개＋viewer XCTest10개 통과 후 최종 정책8개 집중 검증 통과. [세부](progress/phase-4.md). Phase1~4 구현 완료, Phase5 실기기 스크롤·중첩 참여자·가변 높이·줌·메모리 QA가 남는다. 아래 이전 미완료 상태보다 이 기록이 우선한다.

> 2026-09-18 최신: **Phase3 구현 완료·회귀 통과**. 공통 AvatarImagePresentationState/AvatarImageView로 UIKit/SwiftUI 전체 아바타 표시 수명 연결, 방 목록 preview 재사용, 프로필 viewer transient 종료 정리. Swift Testing54개＋XCTest viewer10개 통과, 서비스 오류 분류를 포함한6개 추가 재검증도 통과. [세부](progress/phase-3.md). Phase4 viewport/추가 표시 이벤트, Phase5 실기기QA는 남음. 아래 Phase3 미완료 문구는 과거 상태다.

> 2026-09-18 최신: **Phase2 구현·검증 완료**. 단일 서비스·사용처 정책/DI·썸네일3MiB·원본 transient·사진/세션 무효화·로컬 공용 gate 연결. 사용자 지정 DEV 본인 사진 비교 후 JPEG0.8 승격 적용. 최종48개/10suite 통과, 전체 테스트 target 컴파일·diff check 통과. [세부 결과](progress/phase-2.md). 다음 Phase3 화면 수명·Phase4 viewport/retry·Phase5 기기 QA는 미완료. 아래 미착수/형식 대기 문구는 과거 기록이다.

## 목표

프로필·마이페이지·채팅·룩북 댓글/답글 아바타의 표시·캐시·선로딩·수명을 합의 정책으로 통일한다.

## 완료

- 사용자와 D01~D09 정책 합의.
- 사용자 명시 요청으로 design/decisions/plan/Phase0~5/QA 문서 작성.
- 기존 service/pipeline·프로필 업로드·화면 표시·viewer·세션/정리 접합부를 필요한 범위로 확인했다. 저장 승격과 무캐시 요청은 기존 지원이 아님을 구분했다.

## 미완료·다음 행동

최신 Phase1 공용 코드·자동 회귀 완료: [범위와 결과](progress/phase-1.md), Development Simulator 최종50개/6suite 통과. `.transient` 원본 비저장·옵트인 백그라운드 재인코딩 승격·세대 보호 구현. Phase2 서비스/DI·세션, Phase3 화면·확대, Phase4 선로딩·재시도, Phase5 실기기 검증은 미착수. JPEG/PNG 실제 표본 비교 후 서비스에 encoder를 주입해야 하며,3MiB 호출 통일은 아직 앱에 적용하지 않았다. 아래 진행 중 기록보다 우선한다.

2026-09-18 최신: D11 썸네일3MiB 통일·QA 조정 확정 및 사용자 다음 구현 승인. Phase1 공용 비저장·백그라운드 재인코딩 승격 코드와 fake 회귀 작성 중, Development Simulator build-for-testing 진행. 형식은 아직 미확정이므로 encoder 주입 API만 추가하고 앱에 PNG/JPEG를 임의 채택하지 않는다. 아래 한도 결정 대기는 해소됐다.

최신: D10 필요 시 백그라운드 재인코딩 승격 방식 확정. JPEG/PNG 비교와 다운로드 한도 통일이 남는다. 원본-only 처리는 실제 존재 미확인으로 필수 선행 결정에서 제외했다. 썸네일 생성 기본 긴 변500px·업로드 JPEG0.8 확인. 아래 최초 조사에서 승격 방식/원본-only 결정을 대기한다고 한 내용은 이 상태로 대체한다.

2026-09-18 사용자 구현 착수 승인. Phase0 호출/한도/원본 수명 조사 진행, [조사 결과와 미정 기술 선택](progress/phase-0.md)에 기록했다. 승격용 바이트 확보 방식·서로 다른 기존 한도 처리·원본-only 대체 표시 결정 대기이며 Phase0 전체 완료/Phase1 구현 완료가 아니다. 결정 후 이어서 구현하며 기존 제품 정책/구현 전체를 다시 승인받지 않는다.

## 검증 상태

새 task 문서12개의 내부 상대 링크 검사에서 깨진 링크0, git diff --check 통과. git status와 문서 변경 범위를 확인했다. 앱/테스트 코드 변경 없음, 빌드·자동 테스트·기기 QA 미실행(문서 작성 범위). 구현 시 자동 테스트 실행까지 합의됐다. 서버 배포·커밋·PR 없음.

## 파일과 보존

이번 추가: 이 task의 design.md, decisions.md, decisions/policies.md, plan.md, phases/phase-0~5 상세 문서, qa-checklist.md, progress.md. 포인터 갱신: active.md, HANDOFF.md, ENTRYPOINTS.md, entrypoints/PROFILE.md. 기존 HANDOFF 변경·docs/portfolio/·firestore-debug.log를 보존한다. 상세 task는 기존 ignore 정책을 유지하며 강제 게시하지 않는다.

## 기록 위치

구현 로그는 진행할 때 progress/phase-N.md에 생성한다. 설계 문서에 과거 실행 로그를 누적하지 않는다. 전체 순서는 [plan](plan.md), 기술 선행 사항은 [Phase0](phases/phase-0-contracts.md).
