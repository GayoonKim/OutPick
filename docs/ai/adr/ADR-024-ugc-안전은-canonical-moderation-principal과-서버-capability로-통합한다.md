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
- 텍스트 UGC는 욕설·혐오·위협·금칙어·광고·링크·반복이나 Unicode/공백/기호 우회를 자동 판정하지 않는다. 콘텐츠 안전은 신고·사용자 차단·방 생성자 내보내기와 플랫폼 관리자 사후 검토·제재로 운영하고, 신고 누적은 조사 우선순위에만 사용한다.
- 텍스트 서버 경계에는 의미 판정 대신 타입·빈 값·권한·최대 길이와 canonical moderation principal 기반 기술적 burst limit만 적용한다. Socket는 현재 `max-instances=1` process memory bucket, 댓글·답글은 Functions 인스턴스가 공유하는 Firestore minute bucket을 사용하고 Redis는 보류한다.
- 신규 메시지는 Firestore·Socket·FCM·iOS model·GRDB에 `senderEmail`을 저장·전송하지 않는다. 정상 메시지 원문과 sender payload를 Cloud Logging에 복제하지 않으며 내부 QA 과거 로그는 기존 retention으로 자연 만료시킨다.
- 댓글·답글은 현재 텍스트 전용이며 모든 UGC는 신고·차단·관리자 사후 검수 모델을 사용한다. 이미지·동영상도 외부 의미 판정 provider로 보내지 않고 Phase 7 전용 worker의 기술 검증·metadata 제거만 거친다.
- 댓글·답글 최대 길이는 기존 JavaScript `String.length`와 맞춘 trim 이후 UTF-16 code unit 1,000으로 고정하고 iOS도 `String.UTF16View.count`를 사용한다. `clientRequestID`는 동일 네트워크 재시도 동안 유지하되 입력 수정·취소·성공 후 새 작성에는 재사용하지 않는다.
- 미디어 reservation은 ADR-016을 확장해 상태 머신으로 사용한다. 기술 검증·정규화 완료 transaction 전에는 message document와 room seq를 만들지 않는다.
- Phase 7 미디어는 환경별 quarantine·일반 media·evidence bucket으로 분리한다. quarantine은 soft delete/versioning을 끈 1일 수명 임시 입력이며 공개·evidence에는 raw source를 사용하지 않는다.
- reservation과 processing이 1:1이므로 `MediaUploads`가 lease·attempt·execution·retry까지 통합 소유한다. kind별 Cloud Tasks와 Firestore 고정 slot으로 Production 초기 이미지 4·영상 1 execution만 허용하고 Cloud Run Job 자체 retry는 0으로 둔다.
- exact schema, enum, API, 오류, 상태 전이와 index 계약은 `contracts/chat-moderation-v1.json`을 기준으로 한다.

## 이유

- Firebase UID만 사용하면 같은 provider 계정의 탈퇴·재가입으로 일시 제한·영구 정지와 room ban을 우회할 수 있다.
- HMAC 결과 자체를 제재 ID로 사용하면 key 회전 때 제재와 ban 참조를 모두 바꿔야 하므로 canonical principal과 alias를 분리해야 한다.
- 계정 삭제, 제한, 영구 정지는 허용 capability가 다르므로 단일 `active/inactive` 판정으로는 신고·지원·자기 콘텐츠 삭제·계정 삭제 예외를 안전하게 보존할 수 없다.
- 신고와 삭제를 클라이언트 write로 두면 집계 idempotency, 관리자 동시 처리, audit와 Storage cleanup을 신뢰할 수 없다.
- 미디어 기술 검증·정규화 전에 seq를 할당하면 처리 실패가 영구 gap 또는 불필요한 tombstone을 만든다.
- 단명 source와 공개·신고 객체의 bucket을 분리하면 soft delete, lifecycle, IAM과 보존 정책을 각 목적에 맞게 적용할 수 있다. 고정 slot은 Cloud Tasks dispatcher가 반환된 뒤에도 실행 중인 Cloud Run Job 수를 제한한다.

## 트레이드오프

- 인증 시 provider identity binding과 `moderationAccounts` projection write가 추가된다.
- Rules, Functions, Socket와 Storage가 같은 capability contract를 구현하고 회귀 테스트해야 한다.
- 신고·제재 collection이 서버 전용이므로 앱과 관리자 웹은 callable API에 의존한다.
- 신고된 미디어를 별도 보존하지 않으므로 작성자가 원본을 삭제한 뒤에는 관리자가 미디어를 다시 확인할 수 없다.
- HMAC 원장과 room ban은 가명정보이므로 계정 삭제 후 보존 목적·기간과 접근 통제를 별도로 승인해야 한다.
- ban 사용자의 active room read를 유지하므로 room ban은 기밀성 경계가 아니다. 비공개 방이나 member-only read가 필요해지면 별도 접근 제어 계약이 필요하다.
- 계정 전체 승계는 순간적으로 원자적이지 않다. 대신 owner 중복과 부적격 owner 권한 행사를 방별 transaction·capability로 막고 bounded retry 안의 수렴을 운영 불변식으로 사용한다.
- 자동 텍스트 필터의 오탐과 표현 제한은 피하지만, Apple App Review Guidelines 1.2의 게시 방지 필터 요구를 신고·차단·방 운영·관리자 대응만으로 충족한다고 보장할 수 없는 심사 불확실성을 수용한다.
- Socket process restart 때 짧은 limiter 상태가 초기화된다. 현재 단일 인스턴스 규모에서는 60초 idle TTL·30초 sweep·50,000 cap으로 메모리를 제한하고 이 작은 보호 공백을 수용한다.
- 댓글·답글 write마다 Firestore minute bucket transaction 비용이 추가되지만, Functions 다중 인스턴스에서도 principal당 20/분을 일관되게 적용하기 위해 수용한다.

## 보류한 대안

- 이메일 또는 Firebase UID를 장기 제재 identity로 사용하는 방식은 변경·relay·재가입 우회를 막지 못해 선택하지 않았다.
- HMAC alias를 곧바로 제재 document ID로 사용하는 방식은 key rotation 비용 때문에 선택하지 않았다.
- Firebase Auth disable만 사용하는 방식은 신고·지원·계정 삭제 경로까지 차단하므로 선택하지 않았다.
- room ban 사용자의 list/search/message/media read를 차단하는 방식은 현재 공개 방 읽기 사용자 흐름에 비해 과도하므로 선택하지 않았다.
- owner 승계 중 방 전체를 잠그는 lifecycle은 정상 참여자의 채팅까지 중단하므로 선택하지 않았다.
- 모든 메시지·댓글·답글에 금칙어/Unicode/URL/반복 normalization을 적용하는 방식은 문맥 없는 오탐, 표현 제한과 지속적인 우회 규칙 유지 비용 때문에 선택하지 않았다.
- 현재 규모에서 Redis/Memorystore를 먼저 도입하는 방식은 운영 복잡도와 비용이 이점보다 커서 선택하지 않았다.
- Socket와 동일하게 댓글·답글도 process memory로 제한하는 방식은 Functions 다중 인스턴스 간 quota가 분리되므로 선택하지 않았다.
- 과거 내부 QA Cloud Logging 원문을 별도 삭제하는 방식은 운영 데이터가 없고 기존 retention으로 만료되므로 선택하지 않았다.
- Phase 6에서 관리자 신고 수·과거 제재 이력의 임의 정렬 projection을 추가하는 방식은 관리자 웹 운영 task와 책임이 겹쳐 보류했다.
- 신고 메시지의 모든 첨부를 일괄 복사하는 방식은 개인정보·보존 비용이 크므로 선택하지 않았다. 신고자가 지정한 안정적 `attachmentID`만 결정적 evidence bundle로 보존한다.
- processing 중 message document에 pending 상태를 저장하는 방식은 서버 ready message와 로컬 pending UI 책임을 섞으므로 선택하지 않았다.

## 재검토 조건

- 서로 다른 provider 계정의 명시적 연결 UX를 추가할 때 canonical principal alias 연결 계약을 확장한다.
- 법률·개인정보 검토에서 HMAC 원장 또는 room ban 보존이 허용되지 않거나 별도 동의가 필요하다고 판단할 때 retention과 재가입 방지 범위를 조정한다.
- 선택 미디어 evidence의 접근·삭제 경합·처리 결과별 retention을 Phase 7 계약으로 적용한다. 실제 byte 전달 방식은 관리자 웹 구현 시 재검토한다.
- Socket를 다중 인스턴스로 전환하거나 단일 인스턴스 연결/CPU/메모리/latency 한계, reconnect abuse 또는 프로세스 간 limiter 불일치가 관측될 때 Socket.IO adapter/PubSub와 rate limiter를 Redis/Memorystore의 분리된 keyspace·TTL로 옮긴다.
- App Review가 자동 필터 부재를 문제로 지적하거나 실제 운영에서 신고·차단·사후 대응만으로 안전을 유지하기 어렵다는 근거가 생기면 게시 전 필터 범위를 사용자와 다시 논의한다.
- animated GIF의 frame/decode/memory/CPU 기술 상한은 구현 fixture 결과로 고정한다. App Review가 자동 필터 부재를 문제로 지적하면 의미 판정 도입을 별도 제품 결정으로 재논의한다.
