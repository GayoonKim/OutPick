# Firestore Document ID Boundary Cleanup QA Checklist

## 자동 검증

- [x] Lookbook document ID mapper tests
- [x] Season write payload에 `ID`/`id` 없음
- [x] Chat read/write mapper tests
- [x] CreateRoomUseCase fake repository tests
- [x] Firestore emulator room transaction/rules tests
- [x] `rg '@DocumentID' OutPick` 결과 0
- [x] Phase 1~3 generic iOS Simulator build

## 수동 QA

- [x] 브랜드·시즌·포스트·댓글 조회
- [x] 시즌 write 계약 — `SeasonWriteDTO` payload 자동 테스트로 완료; production 진입점이 없는 직접 생성 UI는 별도 후속 분리
- [x] 전체 방 목록·검색·참여중 목록
- [x] 기존 방 진입
- [x] 이미지 없는 방 생성
- [x] 이미지 있는 방 생성과 background image patch
- [x] 방 정보 수정
- [x] 콘솔에 `I-FST000002`가 발생하지 않음

### Phase 4 수동 QA 기록

- 대상: iOS 26.2 iPhone 17 Pro Max Simulator, 로그인 사용자 `kakao:3647141989`.
- 전체 방 4개, `OOTD` 검색 결과, 참여중 방 4개와 기존 방의 메시지·미디어·Lookbook 공유 복원을 확인했다.
- 기존 `OOTD 공유` 이름에 ` P4QA`를 추가 저장한 뒤 원래 이름으로 원복해 legacy `ID`가 있는 방의 metadata update를 확인했다.
- `P4-NOIMG-0714`와 `P4-IMG-0714`를 생성했다. 이미지 방은 room create 뒤 `thumbPath`/`originalPath` background patch와 Storage 객체 2개를 확인했다.
- 두 QA 방은 방장 종료로 삭제했고 Firestore 문서와 이미지 Storage 객체가 남지 않음을 확인했다.
- Lookbook에서 브랜드 → 시즌 → 11개 포스트 → 포스트 상세 → 빈 댓글 sheet read를 확인했다.
- 전체 수동 QA 로그에서 `I-FST000002`, permission/decode/mapping, 대표 이미지 업로드 실패는 0건이다.
- 시즌 직접 생성 화면 코드는 남아 있으나 `CreateSeasonView`를 만드는 production 호출부가 0개다. URL 후보 import는 별도 worker 작업이므로 임의 실행하지 않았다.
- 사용자 승인 D8에 따라 위 진입점 부재는 이번 task의 blocker로 두지 않고, 직접 생성 진입점 복원 또는 미사용 코드 제거 후속 후보로 기록했다.

## 운영 gate

- [x] Firestore rules 운영 배포 — 2026-07-14 `outpick-664ae`, 사전 Emulator 11/11·dry-run 통과 후 배포 성공
- [x] `Rooms.ID` 4건 삭제 — 사용자 승인 후 경로 ID 일치 조건을 transaction에서 재검증하고 uppercase `ID`만 삭제
- [x] cleanup 전 ID 일치 재확인 — 2026-07-14 Rooms 4건 모두 경로 ID와 일치, `id` 0건
- [x] cleanup 후 `Rooms.ID` 보유 문서 0건 확인 — 방 4개 유지, lowercase `id` 0건, 핵심 불변식 누락 0건
- [x] cleanup 후 로그인 앱 read — 오픈채팅 방 4개 정상 표시, `I-FST000002`·permission/decode/mapping 오류 0건
