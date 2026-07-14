# Firestore Document ID Boundary Cleanup Plan

| Phase | 목표 | 상태 |
| --- | --- | --- |
| Phase 1 | Lookbook DTO의 경로 ID 주입과 Season write DTO 분리 | 구현·자동 검증 완료 |
| Phase 2 | ChatRoom Domain/Firestore 경계와 원자 생성 | 구현·자동 검증 완료 |
| Phase 3 | Firestore rules ID 차단과 emulator 계약 테스트 | 구현·자동 검증 완료 |
| Phase 4 | 통합 검증, 하네스 최신화, 운영 cleanup 승인 gate | 완료 |

Phase별 상세 범위와 gate는 `phases/` 문서를 따른다. 한 Phase가 끝나면 변경 파일, 검증 결과와 남은 위험을 보고하고 다음 Phase 진행 승인을 기다린다.
