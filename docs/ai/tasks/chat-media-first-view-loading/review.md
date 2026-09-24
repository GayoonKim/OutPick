# 채팅 미디어 로딩·원본 수명 PR 리뷰

2026-09-24 자체 리뷰. 외부 리뷰어 승인을 대신하는 기록은 아니다.

## 발견 및 보완

- P2 보완: 영상 재생 hardlink와 Photos 임시 사본은 정상 callback/lease 해제 때만 정리되어 강제 종료 후 잔여가 남을 수 있었다. `PhotoLibraryPreparedResource`를 전용 `tmp/outpick-media-resources` 폴더로 옮겨 다음 프로세스 첫 사용 때 이전 전용 잔여를 정리한다. 기존 원본 캐시/outbox/사용자 사진은 정리하지 않는다. 이 보완 이전 버전의 루트 `PhotoImport-*`는 운영 중 자동 탐색·삭제하지 않으며 OS tmp 관리 대상이다.
- 남은 머지 차단 발견 사항 없음. 변경 diff의 viewport 수요/취소, 공용 다운로드 자원 분리, persistence 세대, 원본 계정 키/pin/삭제, Photos·재생 파일 수명, Container/Coordinator 주입을 대조했다.

## 최종 검증

- Simulator 통합 **186개 통과**: XCTest80 + Swift Testing106. `/private/tmp/outpick-media-pr-tests.log`.
- 범위: viewport/controller/policy/surface/실제 셀, Firebase SDK 취소 재시작 회귀, 파일 다운로드 제한, 직접 디스크 decode/LRU/persistence/revision, 원본 store, viewer, Photos JPEG/MP4/MOV 실제 통합, 영상 닫기6개, resolver, 업로드/메시지 동작, GRDB 삭제/탈퇴 로컬 정리.
- Photos 통합은 Simulator 합성 자료만 사용. 권한 없으면 skip하도록 작성됐으나 이번 실행에서는 실제3개 통과. SDK 테스트는 fake fetcher 서비스이며 운영 객체를 전송/삭제하지 않는다.
- 기기 최종 build 성공: `/private/tmp/outpick-media-pr-device-build.log`. `git diff --check` 통과.
- 앞선 실기기 확인: 사진 확대/재열기/저장, GIF 확대/저장 애니메이션, 로딩 문구 제거, 같은 계정 재로그인/다른 계정 왕복 캐시 분리·재사용. 원본 계정 A80개 유지/B별도1개, 임시0. 실제 영상 저장 재생 보완 후 화면·소리 및 토스트 시각 QA는 대화에서 별도 최종 확인이 명시되지 않았으므로 자동검증과 구분한다.

## 남은 한계/후속

- 7일 만료는 이번 구현 아님. [다음 작업 인계](retention-next-handoff.md)의 전송 시점 기준 정책부터 설계한다.
- 채팅 표시 캐시1GiB/원본512MiB와 전체 로컬 디스크 준비 제한 해제는 기존 사용자 확정값이다. 메모리 압박/LRU 방어는 있으나 저사양 모든 기기 성능을 보장한 결과는 아니다.
- 원본 순서 변경의 이전/이후 사진 크기가 달라 정확한 속도 개선율을 주장하지 않는다. 스트리밍과 명시 저장의 전송 바이트 완전 병합은 하지 않는다.
- UI 전체 자동 순회는 이번 최종 통합에 포함하지 않았다. 기존 단계의 실기기 기록과 현재 unit/component/integration 검증 범위를 구분한다.
