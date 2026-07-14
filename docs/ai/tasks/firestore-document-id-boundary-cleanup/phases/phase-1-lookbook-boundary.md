# Phase 1. Lookbook Document ID Boundary

## 상태

- 구현 완료.
- `FirestoreDocumentIDBoundaryTests` 3개 통과.
- generic iOS Simulator build 통과.
- 수동 Firebase QA는 Phase 4 통합 gate로 유지.

## 목표

- Lookbook DTO 14개의 `@DocumentID`를 제거한다.
- Repository가 `DocumentSnapshot.documentID`를 Domain mapper에 전달한다.
- `SeasonDTO`를 read-only로 만들고 `SeasonWriteDTO`를 분리한다.

## 변경 범위

- `OutPick/Features/Lookbook/Models/DTOs/`
- `OutPick/Features/Lookbook/Models/Mapping/`
- `OutPick/Features/Lookbook/Repositories/Implementations/Firestore*Repository.swift`
- `OutPickTests/FirestoreDocumentIDBoundaryTests.swift`
- 관련 Lookbook/Data/Test 하네스

## 완료 기준

- Lookbook의 `@DocumentID`가 0개다.
- 기본 identity가 필요한 DTO mapper는 비어 있지 않은 `documentID`를 명시적으로 받는다.
- user-state DTO의 사용하지 않는 document ID 선언은 제거한다.
- Season write payload가 read DTO와 분리되고 자기 ID를 encode하지 않는다.
- 기존 부모·컨텍스트 ID와 fallback 의미가 유지된다.

## 검증

- mapper/write payload targeted tests.
- `rg` 정적 경계 검사.
- generic Simulator build.
- 실제 Firebase 읽기·시즌 생성은 수동 QA로 남긴다.

## 논의 필요 사항

- 없음. 사용자 승인 완료.
