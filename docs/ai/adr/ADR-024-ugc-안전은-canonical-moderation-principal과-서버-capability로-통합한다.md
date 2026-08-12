# ADR-024: UGC 안전은 canonical moderation principal과 서버 capability로 통합한다

## 상태

accepted

## 결정

- 계정 생명주기 `users/{uid}.accountStatus`와 안전 제재 `moderationStatus`를 분리한다.
- 장기 제재와 room ban은 Firebase UID가 아니라 서버가 생성한 canonical `moderationPrincipalID`를 기준으로 적용한다.
- Google·Apple·Kakao의 검증된 provider subject는 원문으로 저장하지 않고 versioned HMAC alias로 canonical principal에 연결한다.
- Rules·Functions·Socket·Storage가 읽는 현재 UID projection은 서버 전용 `moderationAccounts/{uid}`로 통일한다.
- 신고 aggregate·submission·audit, 메시지 삭제, room ban과 계정 제재는 클라이언트 직접 write가 아니라 서버 API가 authoritative writer가 된다.
- room ban은 활성 방 콘텐츠의 읽기 visibility를 바꾸지 않고 membership·참여자 전용 Socket·메시지/미디어 write만 차단한다. 내보내기 뒤 기존 읽기 cache는 유지하고 pending write만 취소한다.
- 영구 정지와 계정 삭제 최종 확정의 membership 정리·owner 승계는 계정 전체 단일 transaction이 아니라 durable sweep과 방별 transaction으로 수렴시킨다. 승계 중 일반 채팅은 유지하되 기존 owner capability는 즉시 차단한다.
- 차단은 장기 제재가 아니라 기존 `users/{uid}/blockedUsers/{blockedUID}` 전역 관계를 유지하며, blocked-by-me 단방향 콘텐츠 visibility 정책으로 적용한다. 채팅은 차단 성공 전 현재 window를 보존하고 이후 admission부터 제외하며, 룩북은 현재 댓글·답글을 즉시 숨긴다. 참여자 목록·프로필과 B의 경험은 유지한다.
- 미디어 reservation은 ADR-016을 확장해 상태 머신으로 사용한다. 검사 통과 transaction 전에는 message document와 room seq를 만들지 않는다.
- exact schema, enum, API, 오류, 상태 전이와 index 계약은 `contracts/chat-moderation-v1.json`을 기준으로 한다.

## 이유

- Firebase UID만 사용하면 같은 provider 계정의 탈퇴·재가입으로 일시 제한·영구 정지와 room ban을 우회할 수 있다.
- HMAC 결과 자체를 제재 ID로 사용하면 key 회전 때 제재와 ban 참조를 모두 바꿔야 하므로 canonical principal과 alias를 분리해야 한다.
- 계정 삭제, 제한, 영구 정지는 허용 capability가 다르므로 단일 `active/inactive` 판정으로는 신고·지원·자기 콘텐츠 삭제·계정 삭제 예외를 안전하게 보존할 수 없다.
- 신고와 삭제를 클라이언트 write로 두면 집계 idempotency, 관리자 동시 처리, audit와 Storage cleanup을 신뢰할 수 없다.
- 미디어 검사 전에 seq를 할당하면 검사 실패가 영구 gap 또는 불필요한 tombstone을 만든다.

## 트레이드오프

- 인증 시 provider identity binding과 `moderationAccounts` projection write가 추가된다.
- Rules, Functions, Socket와 Storage가 같은 capability contract를 구현하고 회귀 테스트해야 한다.
- 신고·제재 collection이 서버 전용이므로 앱과 관리자 웹은 callable API에 의존한다.
- 신고된 미디어를 별도 보존하지 않으므로 작성자가 원본을 삭제한 뒤에는 관리자가 미디어를 다시 확인할 수 없다.
- HMAC 원장과 room ban은 가명정보이므로 계정 삭제 후 보존 목적·기간과 접근 통제를 별도로 승인해야 한다.
- ban 사용자의 active room read를 유지하므로 room ban은 기밀성 경계가 아니다. 비공개 방이나 member-only read가 필요해지면 별도 접근 제어 계약이 필요하다.
- 계정 전체 승계는 순간적으로 원자적이지 않다. 대신 owner 중복과 부적격 owner 권한 행사를 방별 transaction·capability로 막고 bounded retry 안의 수렴을 운영 불변식으로 사용한다.

## 보류한 대안

- 이메일 또는 Firebase UID를 장기 제재 identity로 사용하는 방식은 변경·relay·재가입 우회를 막지 못해 선택하지 않았다.
- HMAC alias를 곧바로 제재 document ID로 사용하는 방식은 key rotation 비용 때문에 선택하지 않았다.
- Firebase Auth disable만 사용하는 방식은 신고·지원·계정 삭제 경로까지 차단하므로 선택하지 않았다.
- room ban 사용자의 list/search/message/media read를 차단하는 방식은 현재 공개 방 읽기 사용자 흐름에 비해 과도하므로 선택하지 않았다.
- owner 승계 중 방 전체를 잠그는 lifecycle은 정상 참여자의 채팅까지 중단하므로 선택하지 않았다.
- 신고된 모든 미디어를 moderation Storage에 복사하는 방식은 MVP의 개인정보·보존 비용에 비해 필요성이 입증되지 않아 선택하지 않았다.
- 검사 중 message document에 pending 상태를 저장하는 방식은 서버 ready message와 로컬 pending UI 책임을 섞으므로 선택하지 않았다.

## 재검토 조건

- 서로 다른 provider 계정의 명시적 연결 UX를 추가할 때 canonical principal alias 연결 계약을 확장한다.
- 법률·개인정보 검토에서 HMAC 원장 또는 room ban 보존이 허용되지 않거나 별도 동의가 필요하다고 판단할 때 retention과 재가입 방지 범위를 조정한다.
- 삭제 후 증거 인멸이 실제 운영 문제로 확인될 때 제한적 미디어 evidence 보존을 별도 승인한다.
- Socket를 다중 인스턴스로 전환하거나 reconnect abuse가 관측될 때 rate limiter를 분산 저장소로 옮긴다.
- 미디어 검사 latency·비용 또는 false positive가 허용 범위를 넘을 때 provider, threshold와 영상 상한을 재검토한다.
