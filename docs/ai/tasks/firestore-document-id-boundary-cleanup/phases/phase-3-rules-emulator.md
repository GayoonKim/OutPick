# Phase 3. Firestore Rules and Emulator Contract

## 상태

- 구현 완료.
- Firebase rules dry-run 컴파일 통과.
- Firestore Emulator 계약 테스트 11개 통과.
- 운영 rules 미배포.

## 목표

- Rooms create/update에서 `ID`/`id` 재유입을 차단한다.
- 현재 room/member/joined projection 원자 transaction을 emulator에서 검증한다.

## 변경 범위

- `firestore.rules`
- `firebase.json`
- 신규 `firestore-tests/` 하네스
- Firebase/Test 하네스 문서

## 완료 기준

- 정상 owner transaction은 성공한다.
- 비인증·잘못된 creator/member/joined projection은 전체 실패한다.
- `ID`/`id`가 포함되거나 변경되는 쓰기는 실패한다.
- 기존 `ID`를 변경하지 않는 정상 metadata update는 성공한다.

## 제약

- 이 Phase에서는 운영 rules를 배포하지 않는다.
- 배포는 자동 검증 후 별도 사용자 승인을 받는다.
