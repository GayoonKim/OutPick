# Chat UGC Safety And Room Moderation Decisions

## 상태

- 작업명: `chat-ugc-safety-room-moderation`
- 상태: Phase 0~6 구현·검증 범위 완료. Phase 7 제품·보존·가시성·아키텍처와 Phase 7.1 transport source·저장·처리량·cleanup 설계 확정, Phase 7.0 기술 검증 완료; Phase 7.1 로컬 코드 구현 승인, Development·Production 리소스 생성·배포 미승인
- Phase 4 완료 경계: 실제 기기 background FCM/APNs 검증은 Apple Developer Program 가입과 APNs 설정 후 수행하는 출시 전 외부 gate이며 Phase 4 완료를 막지 않는다. Development 중복 수동 QA는 최신 앱 단일 Production 전환 결정과 Production 두 계정 QA로 대체했다.
- 목적: 채팅 UGC의 서버 권위 삭제, 사용자·방 신고, 전역 사용자 차단, 방 내보내기, 플랫폼 총관리자 사후 제재와 기술적 전송 남용 방어를 하나의 안전 경계로 통합한다.
- 운영 출시 전 필수 확인 조건: 계정 삭제 후 제재 우회 방지용 HMAC 원장과 신고 evidence의 적법한 보존 근거·기간·고지/동의 방식은 개인정보 법률 검토가 필요하다. 이미지·동영상도 자동 의미 검사 없이 신고·관리자 사후 처리로 운영하는 모델이 App Review Guidelines 1.2를 충족하는지는 **확실하지 않음**이며 App Review Notes와 실제 심사 피드백을 출시 gate로 둔다.

## 핵심 정책 근거

- Apple App Review Guidelines 1.2는 UGC 또는 소셜 네트워킹 앱에 부적절 콘텐츠 게시 방지 필터, 공격적 콘텐츠 신고와 신속한 대응, 악성 사용자 차단, 사용자가 쉽게 접근할 수 있는 공개 연락처를 요구한다.
- 2026-08-17 사용자 결정으로 OutPick은 문맥 없는 자동 텍스트 판정의 오탐과 표현 제한을 피하기 위해 욕설·혐오·위협·금칙어·광고·링크·반복 문장 필터를 도입하지 않는다. 신고·사용자 차단·방 생성자의 내보내기/재입장 제한·관리자 사후 검토/제재·고객지원 연락처를 운영 안전장치로 사용한다.
- 자동 텍스트 필터가 없는 이 운영 모델이 App Review Guidelines 1.2의 필터 요구를 충족한다고 보장할 수 있는지는 **확실하지 않음**이다. App Review Notes에 안전 흐름과 실제 운영 경로를 선제적으로 설명하고, 심사 피드백이 있으면 게시 전 필터 도입 여부를 다시 논의한다.
- Apple의 계정 삭제 지침은 법적으로 유지해야 하는 데이터를 제외한 계정 연관 데이터와 사용자 생성 콘텐츠 삭제를 요구한다.
- Google·Apple·Kakao 공식 로그인 문서는 이메일을 계정의 안정적인 고유 식별자로 사용하지 않고 provider가 발급한 고정 user identifier를 사용하도록 안내한다.
- 공식 문서 확인일: 2026-08-07
  - Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
  - Apple 계정 삭제 지침: https://developer.apple.com/support/offering-account-deletion-in-your-app/
  - Google OpenID Connect: https://developers.google.com/identity/openid-connect/openid-connect
  - Sign in with Apple identity token: https://developer.apple.com/documentation/signinwithapple/receiving-a-users-identity-token
  - Kakao Login 이해하기: https://developers.kakao.com/docs/ko/kakaologin/common
  - Kakao Login FAQ: https://developers.kakao.com/docs/en/kakaologin/faq
- Phase 6 자동 텍스트 필터 제외 결정 관련 Apple App Review Guidelines 1.2 재확인일: 2026-08-17
- Phase 7 미디어 자동 의미 검사 제외 결정 관련 Apple App Review Guidelines 1.2 재확인일: 2026-08-18

## 역할과 권한 경계

- OutPick의 제품 계정 역할은 일반 사용자와 플랫폼 총관리자만 사용한다. 브랜드 소유자·브랜드 관리자 계정과 `brands/{brandID}/admins/{uid}` 기반 권한은 이 작업의 채팅 권한 근거로 사용하지 않는다.
- 방 생성자와 후속 임명 방 관리자는 특정 채팅방 안에서만 동작하는 room moderation 역할이다. 플랫폼 총관리자나 제거 대상인 브랜드 소유자·브랜드 관리자와 같은 제품 역할로 취급하지 않는다.
- 방 생성자가 최초 방 관리자다. 다른 사용자에게 방 관리자 권한을 임명하는 기능은 별도 핵심 작업 `chat-room-moderator-delegation`으로 분리한다.
- 방 관리 권한 판정은 공통 room moderation authorization 경계로 모으고 초기 구현은 방 생성자만 허용한다. 후속 `chat-room-moderator-delegation`은 이 경계에 moderator membership을 추가한다.
- 플랫폼 총관리자 제재 API는 Firebase 인증 UID와 서버 전용 `platformAdmins/{uid}` 권한을 검증한다. 로컬 웹의 화면 노출, Google 이메일 비교 또는 localhost 여부만으로 총관리자 권한을 부여하지 않는다.

## 메시지 삭제

- 작성자는 자기 메시지를 삭제할 수 있고, 방 생성자는 자기 방의 모든 메시지를 삭제할 수 있다.
- 메시지는 현재 계약처럼 `isDeleted`로 사용자 표시상의 삭제 여부를 구분하고 삭제 주체별 상태를 추가하지 않는다.
- 메시지 삭제는 서버 API에서 작성자 또는 room moderation 권한을 검증한 뒤 처리한다. Firestore Rules는 클라이언트가 메시지의 `isDeleted`와 다른 서버 관리 필드를 직접 변경하지 못하게 한다.
- 삭제된 메시지의 seq는 tombstone으로 유지해 realtime ordering, read frontier와 gap recovery를 깨지 않는다.
- 삭제 서버 흐름은 메시지 공개 payload, attachments, `mediaIndex`, reply preview, active announcement, `Rooms.lastMessage*`, Storage와 로컬 GRDB/FTS 반영을 하나의 일관된 결과로 수렴시킨다. 즉시 transaction으로 끝낼 수 없는 Storage·projection 정리는 재시도 가능한 서버 cleanup 상태를 사용한다.
- 사용자 화면에는 `삭제된 메시지입니다` 계열 tombstone만 표시한다. 삭제 주체, 삭제 사유와 총관리자 조치는 메시지 문서가 아니라 서버 전용 audit에 기록한다.
- 방 생성자는 타인 메시지에서 대상 사용자를 신고한 뒤 같은 흐름에서 메시지를 삭제할 수 있다. 작성자는 자기 메시지 또는 자기 자신을 신고할 수 없다.

## 신고 모델

- 메시지는 독립적으로 열고 닫는 moderation case가 아니라 사용자 case 아래의 evidence-bearing incident로 취급한다. 같은 메시지의 신고 신호는 별도로 집계하되 작성자 사용자 aggregate에도 사건 1건을 반영한다.
- 사용자에게 제공하는 신고 대상은 `메시지`, `사용자`, `방`이다. 메시지 long press는 `이 메시지 신고`, 프로필과 참여자 목록은 `이 사용자 신고`, 방 설정은 `이 채팅방 신고`로 구분한다.
- 메시지 신고 한 번으로 해당 콘텐츠 사건과 작성자 aggregate를 함께 기록하며, 사용자에게 같은 사건을 메시지와 작성자로 나눠 두 번 신고하게 하지 않는다.
- 방 설정에는 방 신고 진입점을 제공한다.
- 사용자 신고 submission은 대상 사용자, 신고자, 사유, 선택적 상세, 신고가 발생한 방과 선택적 `triggerMessageID`를 문맥으로 저장한다. `triggerMessageID`는 신고 case의 identity가 아니다.
- 사용자 신고는 대상 사용자 중심 aggregate에서 고유 신고자 수, 전체 사건 수, 사유별 집계, 최초·최근 신고 일시와 관련 방을 제공한다. 사건별 submission은 서버 전용 하위 문서로 분리하며, 같은 신고자의 새로운 사건 신고는 허용한다.
- `submitMessageReport`는 evidence가 완전히 확보되기 전 `processing`이며 이 상태를 신고 접수, 신고자 수, queue, 작성자 반복 패턴과 전역 비노출 임계치에 반영하지 않는다. 텍스트 snapshot 또는 메시지 전체 미디어 evidence가 `available`이 된 뒤에만 `accepted`와 canonical incident/reporter/aggregate를 확정한다. evidence 준비가 확정 실패하면 `failed`로 끝내고 부분 evidence와 source hold를 정리한다.
- 같은 `clientRequestID` 재전송은 transport replay로 보고 revision과 무관한 최상위 `moderationMessageReportRequests/{requestID}`를 현재 review revision 결정 전에 먼저 조회한다. 앱은 최초 신고 UUID를 로컬에 보존해 terminal 결과까지 같은 ID로 확인한다. `processing`이면 같은 준비 작업을, `accepted | failed | messageAlreadyDeleted`면 최초 결과를 반환하므로 관리자 종결 뒤 늦게 도착한 과거 요청이 새 revision 신고가 되지 않으며 transport quota도 다시 소비하지 않는다. 같은 reporter/message/reviewRevision의 새 `clientRequestID`는 새 receipt transport slot 1개를 소비하되 준비 중이면 기존 결정적 bundle 작업을 이어서 확인하고, 이미 접수됐으면 `alreadyReported`를 반환해 앱이 `이미 신고한 메시지예요`를 표시한다. evidence·moderation 신고 집계는 중복 증가시키지 않는다.
- 메시지 신고는 review revision별 reporter 한 건만 저장하고 기각·해결 뒤 새 revision이 열리면 같은 reporter도 다시 신고할 수 있다. 프로필 사용자 신고와 방 신고는 기존 사건별 새 UUID 허용 계약을 유지한다.
- 사용자·방 신고 aggregate의 누적 통계는 닫히거나 다시 열리는 case가 아니다. 관리자 작업 상태 `reviewState`만 `open → inReview → resolved | dismissed`로 전이하며, 종료 뒤 새 사건이 접수되면 `reviewState`를 `open`으로 바꾸고 `reviewRevision`을 증가시킨다.
- `caseVersion`은 신고 횟수가 아니라 관리자 동시 수정 충돌을 막는 optimistic concurrency version이다. 모든 관리자 상태 변경은 읽은 `caseVersion`을 제출하고 서버는 stale mutation을 거부한다.
- 신고 사유는 채팅과 룩북에서 공통 canonical taxonomy를 사용하고 화면 표시명만 기능별로 분리한다. 초기 canonical 사유는 `욕설·괴롭힘`, `혐오 표현`, `성적 콘텐츠`, `스팸·광고`, `개인정보 노출`, `불법·위험`, `기타`다.
- 메시지 신고는 attachment 선택이나 동영상 시점 입력을 요구하지 않는다. 텍스트는 제한된 원문 snapshot, 이미지 묶음은 해당 메시지의 정규화 `display` 전체, 동영상은 정규화 원본 전체 1개를 서버 전용 evidence로 보존한다. 프로필 사용자 신고처럼 특정 메시지가 없으면 미디어 evidence를 만들지 않는다.
- 결정적 `moderationMessageEvidence` bundle은 versioned canonical tuple의 `roomID + messageID + reviewRevision` 기준으로 만들고 제한된 text snapshot과 전체 attachment manifest를 공통 소유한다. 첫 신고 준비가 전체 attachment copy를 요청하고 같은 revision의 후속 요청은 기존 bundle/object를 재사용해 중복 복사하지 않는다. incident는 `roomID + messageID`, submission은 incident/revision/reporter/clientRequestID의 versioned canonical tuple SHA-256이며 최초 review revision은 기존 신고 계약과 같은 0이다.
- 신고 성공만으로 신고자 화면의 메시지를 자동 숨기지 않는다. 신고, 개인 메시지 숨김, 사용자 차단, 서버 전역 비노출을 서로 다른 사용자 액션과 상태로 유지한다. 개인 `이 메시지 숨기기`는 후속 UX 범위이며 자동 실행하지 않는다.
- 별도 `moderationReviewQueue` projection은 만들지 않는다. `moderationMessageIncidents`, `moderationUserReports`, `moderationRoomReports`가 canonical 원장이자 관리자 조회 source이며 관리자 API가 각 원장을 직접 필터·정렬한다.
- 일반 단일 메시지 신고는 incident `queueClass=holding`에 저장해 검색·사용자/메시지 상세에서 조회 가능하게 한다. 같은 메시지 고유 신고자 2명이면 `reviewRequired`, 긴급 첫 신고면 `urgent`로 바꾼다. `holding && reviewDueAt <= serverNow`는 문서 상태를 바꾸는 scheduler 없이 관리자 조회 조건으로 검토 목록에 포함한다.
- 같은 작성자의 최근 7일 서로 다른 신고 메시지 3개 이상과 그 메시지 전체의 고유 신고자 2명 이상이 함께 충족되면 사용자 aggregate를 검토 대상으로 표시한다. 작성자 아래 `reportedMessages`와 `messageReporters` marker를 분리해 최근 3개/2개까지만 읽고, `messagePatternReviewUntil = min(세 번째 최신 메시지 시각, 두 번째 최신 신고자 시각) + 7일`을 서버 시각과 비교해 scheduler 없이 만료한다. 한 사람이 메시지 3개를 연속 신고하거나 한 메시지를 여러 명이 신고한 경우는 이 반복 작성자 기준을 충족하지 않는다.
- 긴급 사유(`sexual`, `privacy`, `illegalDangerous`)는 첫 신고부터 긴급 큐에 표시한다. 전역 임시 비노출은 같은 review revision의 24시간 기준 긴급 고유 신고자 2명 또는 사유와 관계없는 전체 고유 신고자 3명에 도달하거나 관리자가 수동 조치할 때만 적용한다.
- 24시간·7일 rolling window는 transaction에서 고정한 단일 서버 시각을 사용하고 시작 경계를 포함한다. `reviewDueAt <= serverNow`는 overdue, `messagePatternReviewUntil > serverNow`만 활성으로 판정한다.
- 총 submission 수, 고유 신고자 수, 신고된 서로 다른 메시지 수와 관리자 확정 경고 수를 분리한다. 신고만으로 경고나 계정 제재를 자동 증가시키지 않으며, 확정 위반은 최근 90일 `confirmedViolationCount90d`와 활성 경고를 관리자 판단 보조 정보로만 제공한다. 1회 경고·2회 제한 검토·3회 이상 장기 제한/정지 검토는 운영 권고일 뿐 자동 제재 규칙이 아니다.
- Evidence 원본은 클라이언트에 공개되지 않으며, 활성 플랫폼 관리자가 서버 인증을 거쳐 특정 evidence 객체만 제한적으로 조회한다. 실제 byte 전달 방식과 접근 UI는 `admin-web-operations-migration`에서 관리자 웹을 구현할 때 재검토·수정할 수 있으며, 브라우저에 service account credential을 두거나 일괄 다운로드를 허용하지 않는다.
- 신고 접수, 집계, 필터링과 제재 상태 적용은 관리자 웹 실행 여부와 무관하게 클라우드에서 항상 동작한다. 로컬 관리자 웹은 저장된 신고를 조회하고 처리하는 UI이며 서버 처리의 가용성 조건이 아니다.
- 총관리자는 사용자·방 신고를 기각하고, 참조된 메시지가 존재하면 삭제하며, 대상 계정에 일시 제한 또는 영구 정지를 적용할 수 있다. 방 신고에 대한 관리자 종료는 일반 방장 삭제와 구분되는 `closedByModeration` lifecycle을 먼저 적용해 신규 가입·쓰기·Socket·push를 차단하고 사용자 안내와 감사 가능성을 보존한다. 물리 정리는 별도 재시도 가능한 cleanup으로 수렴시킨다.
- 앱 내 마이페이지, 신고 완료 화면과 제재 안내 화면에서 동일한 고객지원 경로에 접근할 수 있어야 한다. App Store Support URL과 앱 내 연락처는 최신 상태를 유지한다.
- 내부 신고 대응 SLO 초기값은 긴급 신고 24시간, 일반 신고 72시간이다. 사용자에게 법적 처리 기한으로 약속하는 값이 아니라 운영 경고와 미처리 정렬 기준으로 사용한다.

## Phase 7.4B evidence-first transaction 확정 — 2026-08-24

- Phase 7.4B는 `submitMessageReport`의 parser·service·신고/삭제 transaction과 자동 테스트까지만 구현한다. 미디어 copy/cleanup, Rules/index와 iOS UX가 준비되기 전에는 root `functions/src/index.ts`에 callable을 export하거나 Development/Production에 배포하지 않는다.
- 앱과 신규 미디어 schema가 아직 외부 배포되지 않았고 기존 메시지는 테스트 데이터뿐이므로 legacy media evidence fallback은 만들지 않는다. 신규 attachment가 `attachmentID`, ready display `bucket/path/generation/bytes/contentType`을 함께 저장하게 하고 신고 활성화 전 기존 테스트 메시지·미디어는 별도 승인된 정확한 cleanup으로 제거한다.
- 신고 가능한 사용자 작성 메시지는 `text | image | video | lookbookShare`다. lookbook share는 bounded 본문과 서버가 이미 검증한 `sharedContent` 표시 snapshot을, reply는 target 메시지에 포함된 bounded preview 문맥만 evidence에 넣는다. reply 대상 원문·미디어를 따라가 추가 복사하지 않는다.
- 같은 reporter는 같은 message review revision에 신고 한 건만 가진다. processing 재요청은 최초 reason/detail과 기존 preparation을 재사용하고 accepted 뒤 새 `clientRequestID`는 reason/detail 변경 없이 `alreadyReported`를 반환한다. 같은 `clientRequestID`에 다른 payload가 와도 최초 요청 결과를 권위로 반환한다. 서로 다른 reporter의 reason/detail은 revision reporter 문서에 각각 보존하고 reason별 집계를 독립 계산한다.
- transport request receipt는 preparation 하위가 아니라 최상위 `moderationMessageReportRequests/{requestID}`에 두며 `requestID = hash(incidentID, reporterModerationPrincipalID, clientRequestID)`로 계산해 reviewRevision을 포함하지 않는다. receipt를 먼저 조회한 뒤 없을 때만 현재 revision과 preparation을 결정한다. receipt에는 식별자·상태·시각·오류 코드만 저장하고 신고 detail이나 evidence 원문은 중복 저장하지 않는다.
- evidence 실패 request receipt는 원래 generation의 failed 결과로 남긴다. bundle `state=failed`는 partial destination cleanup 완료와 빈 `objectPaths`까지 포함하는 terminal 상태이며, 이 상태와 preparation/copy job의 동일 generation을 확인한 뒤 새 `clientRequestID`만 같은 deterministic preparation/bundle/job ID를 모두 `attemptGeneration + 1`로 원자 재시작할 수 있다. processing alias receipt는 preparation이 terminal이면 재조회 시 한 건씩 결과를 수렴하고, receipt generation보다 preparation generation이 높으면 이전 attempt가 failed였음을 확정한다. 이전 generation worker·callback은 generation precondition이 다르면 아무 상태도 변경하지 않는다.
- evidence available drain은 preparation 최대 30건과 각 preparation의 `initialRequestID` receipt만 함께 확정한다. 같은 preparation을 가리키는 추가 UUID receipt 전체를 무제한 query/write하지 않으며, 각 alias는 동일 UUID 재조회 때 preparation의 저장된 queue/visibility/accepted 시각으로 개별 수렴한다.
- `requestedAt`은 최초 유효 신고 intent 시각, `acceptedAt`은 evidence 전체 확보 시각이다. canonical `receivedAt`, 24시간·7일 window와 운영 SLO는 `requestedAt`을 사용하지만 count·queue·visibility 효과는 `acceptedAt` 이후에만 기록한다.
- 신고 권한은 `report` capability와 활성 room read context를 함께 요구한다. 현재 member와 기존 메시지 read가 유지된 active room-ban 사용자를 허용하고, 자기 신고는 UID가 아니라 canonical moderation principal 기준으로 거부한다. `visible | hiddenPendingReview`는 신고 가능하며 삭제 tombstone은 `messageAlreadyDeleted`로 끝낸다.
- public ready media 삭제를 담당하는 기존 `chatMessageCleanupJobs`에 `awaitingEvidence`를 추가하고 cleanup worker는 이 상태를 claim하지 않는다. text evidence는 즉시 available이므로 public cleanup을 바로 pending으로 만들고, media는 copy 성공 또는 terminal failure로 source read가 끝난 뒤 pending으로 전환한다. copied moderation evidence cleanup은 별도 `moderationEvidenceCleanupJobs`가 담당한다.
- 최초 media bundle이 available이 되면 processing preparation들을 accepted로 drain하는 동안 incident를 `draining`, 모두 확정된 뒤 `reviewable`로 둔다. 관리자는 `reviewable` revision만 종결할 수 있다. 관리자 삭제가 먼저면 남은 요청은 `messageAlreadyDeleted`와 client-safe `moderationRemoved` tombstone으로 끝내고, 기각 뒤 메시지가 남아 있으면 이후 유효 신고는 새 revision과 새 evidence bundle로 시작한다.
- 신고 기술 limiter는 reporter moderation principal 기준 user/room/message 합산 1분 10회다. 기존 accepted user/room 요청과 이전에 보지 못한 message `clientRequestID`의 최상위 transport receipt 생성을 합산한다. 정확히 같은 `clientRequestID` replay만 무료이며, 새 UUID는 기존 processing preparation 재사용·`alreadyReported`·`messageAlreadyDeleted` 결과여도 receipt 1건을 만들므로 transport slot 1개를 소비한다. 이는 moderation 신고 count·queue·evidence 증가와 분리된다. 새 semantic preparation 여부는 별도 `messagePreparationCount`로 관측하되 한 요청을 기술 작업 2회로 세지 않는다.
- 관리자 삭제 tombstone은 구체적 신고 사유·신고자·관리자 정보를 client에 노출하지 않고 `deletionPresentation=moderationRemoved`만 제공한다. 일반 자기 삭제·방장 삭제는 기존 generic `deleted` 표시를 유지한다.

## Phase 2 신고 rate limit과 구현 경계 — 2026-08-10

- 신고 rate limit은 정상 사용자의 일일 신고 가능 횟수를 제한하는 정책이 아니라 자동화된 단기 폭주로부터 신고 집계·관리자 queue·Firestore를 보호하는 최후 방어선으로 사용한다.
- 일일 hard cap과 동일 대상 일일 hard cap은 두지 않는다. 인증·App Check·동일 `clientRequestID` idempotency를 먼저 적용하고, 서로 다른 사건 ID를 짧은 시간에 자동 생성하는 요청만 reporter moderation principal 기준 1분 10건으로 제한한다.
- 같은 `clientRequestID` 재전송은 rate counter를 소비하지 않고 기존 접수 결과를 반환한다. 제한 응답은 `RATE_LIMITED/resource-exhausted`와 재시도 가능 시각을 제공하며 신고 detail은 rate-limit 문서나 로그에 저장하지 않는다.
- iOS는 Phase 2에서 신고 Domain 모델, Repository/UseCase와 Cloud Functions adapter까지만 구현한다. 신고 화면·Coordinator route·완료 화면은 Phase 8에서 서버 계약에 연결한다.
- Phase 2 관리자 처리는 신고 목록·상세·검토 상태 mutation과 계정 일시 제한·영구 정지·해제를 포함한다. 메시지 삭제와 방 `closedByModeration` mutation은 Phase 3의 cleanup/lifecycle 계약과 함께 구현한다.
- 기존 Lookbook `commentReports` 저장 계약과 UI는 Phase 2에서 migration하지 않는다. Chat 사용자·방 신고와 관리자 API만 신규 canonical moderation report 경계에 연결한다.
- 구현과 로컬 자동 검증까지만 승인한다. Development/Production 배포, `platformAdmins` 실제 권한 부여, 실데이터 생성·migration과 TTL 활성화는 각각 별도 승인을 받는다.

## 전역 사용자 차단

- 룩북, 채팅과 프로필은 `users/{uid}/blockedUsers/{blockedUID}` 기반의 하나의 전역 사용자 차단 관계를 공유한다. 채팅 전용 차단 collection을 별도로 만들지 않는다.
- A가 B를 차단하면 A의 visibility 경계만 B 콘텐츠를 제외한다. B의 참여자 목록·프로필·공동방·콘텐츠와 상호작용 경험은 바꾸지 않고 차단 사실을 직접 또는 간접 안내하지 않는다.
- 참여자 목록과 프로필 진입은 양쪽 모두 유지한다. 다만 A가 B에게 답글·멘션·초대처럼 직접 상호작용하려 하면 A에게만 `먼저 차단을 해제해 주세요`를 안내하고 자동 해제하지 않는다.
- 공동 채팅방 membership은 유지한다. 방 내보내기와 room ban은 사용자 차단과 별도 기능이다.
- 채팅에서 차단 성공 전에 현재 `ChatMessageWindowStore`에 admission된 B의 메시지는 현재 화면 세션 동안 그대로 둔다. 차단 성공 시 기존 window를 prune하거나 collection view를 강제 reload하지 않고 GRDB·FTS·미디어 캐시 원문도 소급 삭제하지 않는다.
- 차단 성공 뒤 수신하는 Socket 이벤트, 새 pagination batch, 재진입·재동기화·window eviction 뒤 다시 admission되는 B의 메시지는 작성 시각과 무관하게 placeholder 없이 제외한다. UI render 시 기존 배열 전체를 재필터링하지 않고 persistence/presentation 전 admission 경계에서 판정한다.
- 숨긴 메시지도 Socket strict ordering seq와 원본 pagination cursor는 소비해 gap recovery와 같은 page 재요청이 반복되지 않게 한다. 별도 redacted message row는 만들지 않는다.
- 로컬에 이미 남은 원문을 물리 삭제하지 않으므로 검색, 미디어 갤러리, reply preview, 공지, 방 목록 preview와 앱 내 banner가 결과를 UI에 새로 admission할 때 같은 visibility Store로 제외한다. 숨긴 메시지는 visible unread와 사용자 preview를 증가시키지 않는다. 방 종료·제재 같은 서버 시스템 이벤트는 사용자 차단과 무관하게 표시한다.
- Socket room broadcast는 유지할 수 있으며 iOS admission/visibility 경계가 차단 대상을 제외한다. 차단은 기밀성 접근 제어가 아니라 사용자 가시성 정책이므로 MVP에서 사용자별 Socket fan-out을 강제하지 않는다.
- FCM fan-out은 수신자의 전역 차단 관계를 서버에서 확인해 B가 보낸 push를 A에게 전송하지 않는다.
- iOS는 계정별 차단 UID 목록의 마지막 성공 snapshot만 로컬에 보관한다. 로그인 세션 시작 시 이를 메모리 `BlockVisibilityStore`에 올리고 서버 owner-only relation 최신값으로 원자 교체한다. 서버 조회 실패 시 마지막 성공 snapshot을 유지하며 snapshot이 한 번도 없으면 UGC 진입을 첫 조회 성공까지 fail closed한다.
- 차단·해제 mutation은 서버 성공 뒤 메모리와 로컬 snapshot을 갱신한다. 차단 해제 시 현재 채팅 화면을 강제 재조회하지 않고 이후 메시지는 즉시 표시하며, 차단 중 제외된 과거 메시지는 방 재진입·pagination·일반 동기화 때 자연 복원한다.
- 룩북 댓글·답글은 채팅의 현재-window 보존 예외를 사용하지 않는다. 차단 성공 즉시 현재 화면에서 B 콘텐츠를 숨기고 이후 조회도 단방향 blocked-by-me relation만 적용한다.
- 아직 외부 배포·운영 중인 앱이 없으므로 Phase 4에서 구버전 양방향 visibility 호환이나 단계적 최소 버전 cutover를 두지 않고 최신 계약으로 통일한다.

## 계정 일시 제한과 영구 정지

- 계정 생명주기 `accountStatus`와 안전 제재 `moderationStatus`를 분리한다. 기존 `active | deletionPending` 계약에 제재 상태를 직접 섞지 않는다.
- 일시 제한 사용자는 로그인과 읽기, 신고, 차단·해제, 자기 콘텐츠 삭제, 계정 삭제와 고객지원 접근을 계속 사용할 수 있다.
- 일시 제한 동안 채팅·미디어·댓글·답글 등 UGC 생성·수정, 방 생성과 방 가입을 서비스 전체에서 차단한다.
- 영구 정지 사용자는 일반 앱 콘텐츠에 진입하지 못하고 제재 안내, 고객지원과 계정 삭제 경로만 사용할 수 있다.
- Firebase Auth disable만을 제재 경계로 사용하지 않는다. Firestore Rules, Functions, Socket와 Storage가 같은 moderation capability 정책을 검사하고 기존 Socket을 즉시 종료한다.
- 제한 기간은 서버 시각의 `restrictedUntil`로 판정한다. 만료 정규화 scheduler가 지연돼도 요청 시각 판정으로 만료된 제한을 계속 적용하지 않는다.
- 영구 정지와 해제 같은 고위험 총관리자 조치는 최근 재인증을 요구한다.

## 탈퇴·재가입 제재 우회 방지

- Firebase UID, 이메일 또는 `accountGenerationID`만으로 일시 제한, 영구 정지와 room ban의 장기 subject를 식별하지 않는다.
- provider가 검증한 안정적인 user identifier를 사용한다.
  - Google: ID token의 `sub`
  - Sign in with Apple: Apple user identifier/`sub`
  - Kakao: service user ID
- 이메일은 변경 가능하고 선택적이며 Apple private relay가 존재하므로 제재 identity와 provider 간 자동 계정 연결에 사용하지 않는다.
- 서버는 검증된 provider token에서 `provider + providerSubject`를 직접 추출하고 서버 비밀키로 versioned HMAC alias를 계산해 canonical `moderationPrincipalID`에 연결한다. 클라이언트가 provider subject, HMAC 결과 또는 `moderationPrincipalID`를 권위 값으로 제출하지 않는다.
- HMAC alias는 같은 provider 계정이 재가입하면 같은 결과가 되고 원래 provider subject를 복호화할 수 없는 결정적 가명 식별자다. 단순 SHA-256은 예측 가능한 provider ID 대입 공격을 막지 못하므로 사용하지 않는다. 제재와 room ban은 회전 가능한 HMAC 결과 자체가 아니라 canonical `moderationPrincipalID`를 기준으로 적용한다.
- moderation 원장에는 원본 이메일, provider subject와 provider token을 저장하지 않는다. HMAC key는 서버 secret으로 보관하고 alias에 key version을 기록한다. key 회전 시 기존 alias를 즉시 덮어쓰지 않고 새 alias를 같은 `moderationPrincipalID`에 연결한 뒤 검증·전환한다.
- 같은 사람이 서로 다른 Google·Apple·Kakao 계정을 사용한 경우 자동으로 동일인이라고 판정하지 않는다. 사용자가 인증된 상태에서 명시적으로 provider 계정을 연결한 경우에만 하나의 moderation principal로 연결한다.
- Kakao의 `User ID Fixed` 설정이 활성화돼 탈퇴·연결 해제 후 동일 계정의 service user ID가 유지되는지 구현 전 콘솔과 실제 Development 재연결 QA로 확인한다.
- HMAC은 완전한 익명정보가 아니라 동일인을 다시 구분할 수 있는 가명 식별자다. 계정 삭제 후 이를 보존할 목적, 기간, 접근 권한과 고지/동의 또는 법적 근거는 개인정보 처리방침과 법률 검토를 거쳐야 한다.

## Phase 1 종료와 Sign in with Apple 후속 분리 — 2026-08-07

- 사용자 결정으로 Phase 1의 실제 provider QA 범위는 현재 앱이 지원하는 Google·Kakao로 닫는다. 두 provider 모두 Development 실제 탈퇴·재가입 뒤 기존 restricted principal 복원을 확인했으므로 Phase 1 구현·Development rollout을 완료 처리한다.
- 서버 identity 계약의 Apple provider mapping은 유지하지만 현재 iOS 로그인 UI·Repository·재인증 흐름에는 Sign in with Apple 진입점이 없다. Apple 로그인은 Phase 1 미완료 항목으로 끌고 가지 않고 별도 후속 작업으로 기록한다.
- 후속 Apple 작업은 App Store 정책과 Apple/Firebase 콘솔 선행 조건, 로그인 UI, Repository/UseCase/DI, 계정 삭제 재인증, provider subject 검증, Development 탈퇴·재가입 QA를 구현 전에 다시 설계한다. 세부 요구사항·계획·구현은 미승인이다.
- Kakao custom-token의 요청 token claim은 Firebase Admin `UserRecord.customClaims`에 영구 보관되지 않아 기존 Auth backfill dry-run이 Kakao를 unresolved로 표시한다. 현재 로그인 bootstrap과 탈퇴·재가입 복원은 통과했지만 Production rollout 전에는 기존 Kakao 계정의 안전한 migration 경계를 별도로 보완·검증한다.
- 이 완료 판단은 Development 범위다. Production moderation Secret·backfill·Functions·Rules·Storage·Socket 변경과 개인정보 보존 승인을 포함하지 않는다.

## Phase 1 Production readiness 지원 경로 결정 — 2026-08-07

- 현재 Production 앱은 개발자·내부 QA만 사용하며 외부 사용자 배포 상태가 아니다.
- 현재 고객지원 웹 URL과 문의 이메일이 없으므로 Phase 1 Production 인프라의 내부 smoke에서는 `supportURL: null`을 유지할 수 있다.
- 이 예외는 내부 QA에만 적용한다. `supportURL: null`인 동안 Production에서 restricted/suspended 상태를 실제 운영하지 않고, App Store 제출·TestFlight 외부 테스터 공개·일반 사용자 배포를 진행하지 않는다.
- HTTPS 고객지원 페이지는 별도 `customer-support-https-page` 후속 작업으로 분리한다. 문의 수단, 제한 이의제기, 신고 처리 문의, 개인정보 처리방침과 계정 삭제 안내를 포함하고, 완성된 URL을 moderation API와 앱의 공개 지원 경로에 연결한 뒤 외부 배포 gate를 해제한다.

## Phase 1 Production readiness HMAC·Kakao migration 결정 — 2026-08-07

- 사용자 승인으로 Production readiness 단계에서는 내부 계정의 active principal/alias 생성과 active capability smoke만 허용한다. restricted/suspended 상태 적용과 Production 탈퇴·재가입 QA는 수행하지 않는다.
- 계정 삭제 후 moderation HMAC 원장 보존 기간·법적 근거·고지는 개인정보 처리방침과 고객지원 페이지 준비 때 확정한다. 확정 전에는 외부 사용자 배포와 Production 계정 삭제 후 제재 원장 보존 QA를 진행하지 않는다.
- 기존 Kakao Auth migration은 Firebase UID의 `kakao:{id}`를 곧바로 신뢰하지 않는다. UID에서 얻은 후보를 Production `KAKAO_ADMIN_KEY`로 Kakao 사용자 조회 API에 전달하고, 연결된 사용자 ID가 정확히 일치할 때만 provider identity로 승인한다.
- Kakao provider user ID는 migration 프로세스 메모리에서만 사용한다. Firestore moderation 문서, 로그, migration 결과, Firebase persistent custom claims에 새로 저장하지 않는다.
- Production dry-run은 provider별 resolved/unresolved 건수만 출력한다. apply는 사용자 수·provider별 예상 건수와 Production 확인 문자열을 모두 요구하고, 한 계정이라도 불명확하거나 예상 건수가 다르면 쓰기 전에 전체 중단한다.
- backfill apply는 alias/principal/account transaction의 기존 idempotency를 유지한다. 부분 실패 시 재실행으로 수렴할 수 있어야 하며 raw provider identity를 rollback 자료로 남기지 않는다.

## 방 내보내기와 room ban

- 방 생성자가 사용자를 내보내면 서버는 membership 제거, 사용자 joined-room projection 정리, memberCount 갱신, room ban 기록과 Socket 즉시 퇴장을 일관되게 처리한다.
- room ban은 Firebase UID가 아니라 canonical `moderationPrincipalID`에 연결해 같은 provider 계정으로 탈퇴·재가입해도 우회하지 못하게 한다.
- room ban은 읽기 차단이 아니라 membership·쓰기 차단이다. ban 사용자도 활성 방 목록·검색·preview, 기존 메시지와 공개 미디어를 읽을 수 있지만 membership 생성·재가입, 참여자 전용 Socket join과 메시지·미디어 전송은 할 수 없다.
- 내보내기 성공 뒤 현재 채팅 화면은 기존 메시지·FTS·완료 미디어 cache를 지우지 않고 읽기 전용 non-member 상태로 전환한다. pending outbox·미완료 업로드는 취소하고 joinedRooms 기반 push·banner·공유 대상 노출은 membership 제거로 제외한다.
- 방 생성자는 ban 목록에서 재입장 금지를 해제할 수 있다. 해제는 재가입을 허용할 뿐 membership을 자동 복구하지 않는다.
- ban 목록은 ban 시점의 최소 표시 snapshot만 사용하고 재가입한 새 UID의 최신 프로필과 연결하지 않는다. 자유 입력 사유는 저장하지 않고 canonical 신고 사유 enum만 사용한다. 플랫폼 총관리자는 고객지원·오류 복구를 위해 감사 로그를 남기는 서버 전용 unban 경계를 가질 수 있지만 일반 앱 UI에는 노출하지 않는다.
- 방이 삭제되면 해당 방의 room ban 원장도 정리한다. 계정 삭제 후 room ban subject를 보존하는 기간과 법적 근거는 위 개인정보 검토 범위를 따른다.

## 방 생성자 이탈·삭제·정지

- 방 생성자가 수동으로 방을 나가려는 경우 현재 계약처럼 명시적 방 삭제로 처리한다. 일반 사용자에게 임의 owner 이전 UI를 제공하지 않는다.
- 일시 제한과 취소 가능한 `deletionPending`에서는 owner를 이전하지 않는다. 일시 제한 owner는 만료 전까지 관리 권한만 잃고, 계정 삭제 최종 확정 또는 영구 정지에서만 승계를 시작한다.
- 계정 전체를 하나의 transaction으로 바꾸지 않는다. 제재·삭제 상태를 먼저 권위 상태로 반영하고 durable succession job이 각 방을 별도 transaction으로 처리한다. 승계 중에도 일반 member의 채팅은 유지하되 기존 owner는 capability 경계에서 관리·전송할 수 없다.
- 영구 정지 사용자는 소유 방뿐 아니라 모든 채팅방 membership·joinedRooms에서 제거하며, 정지 해제 뒤 membership과 owner를 자동 복원하지 않는다. 계정 삭제 최종 cleanup도 같은 공용 membership sweep·승계 경계를 사용한다.
- successor는 `joinedAt`이 가장 오래된 적격 활성 member를 사용한다. room ban, `deletionPending`, 실효 일시 제한과 영구 정지 사용자는 제외하고, 동률은 UID 오름차순, `joinedAt` 누락 legacy member는 정상 시각 보유자 뒤에 둔다.
- 방별 transaction은 `Rooms.creatorUID`, 기존/신규 owner member role, joinedRooms role, 삭제·정지 사용자의 membership과 memberCount를 함께 수렴시킨다. 후보가 transaction 직전에 부적격해지면 다음 후보로 재시도한다.
- 적격 successor가 없으면 계정 삭제는 `closedByOwner`, 영구 정지는 `closedByModeration`으로 기존 Phase 3.1 종료 lifecycle에 수렴시킨다.
- 승계 중 별도 room lifecycle 잠금은 추가하지 않는다. 완료 불변식은 owner 중복 0, 부적격 owner의 권한 행사 0, bounded retry 안의 적격 owner 또는 방 종료 수렴이며 영구 실패는 운영 queue에 보존한다.
- 후속 `chat-room-moderator-delegation`이 구현되면 위임된 활성 moderator를 successor에서 우선하는 방향으로 별도 task에서 확장한다.

## Phase 3 메시지 삭제·방 폐쇄·안내 확정 — 2026-08-10

- 메시지 삭제는 `deleteChatMessage`만 수행한다. 작성자는 자기 메시지, 방 생성자는 자기 방의 모든 메시지, 활성 platform admin은 최근 인증과 사유가 있을 때 모든 메시지를 삭제할 수 있다.
- 삭제 transaction은 `seq`와 `isDeleted` tombstone을 유지하고 본문·첨부·공유 payload·검색 payload·발신자 snapshot을 즉시 제거한다. 마지막 메시지와 공지 projection도 같은 transaction에서 정리한다.
- reply preview·media index·Storage는 deterministic `chatMessageCleanupJobs`가 정리하며 5분 scheduler와 최대 20회 재시도로 수렴한다. 완료 job은 7일 TTL, 최종 실패 job은 TTL 없이 운영 확인 대상으로 남긴다.
- 방장 삭제는 `closedByOwner`, 관리자 폐쇄는 `closedByModeration`으로 구분한다. 두 경로 모두 room lifecycle을 즉시 닫아 Firestore read/join/write, Storage read/write와 Socket 입장을 차단하고 방 콘텐츠 물리 정리를 바로 시작한다.
- 방장 삭제는 삭제를 수행한 creator를 제외한 당시 member에게, 관리자 종료는 creator를 포함한 당시 member에게 `users/{uid}/roomClosureNotices/{roomID}`를 만든다. 사용자가 확인하면 해당 notice를 즉시 삭제하며, 미확인 notice만 `expiresAt` 기준 최대 30일 보존한다.
- 30일은 방과 메시지 콘텐츠 보존 기간이 아니다. 방 콘텐츠는 안내 생성 후 즉시 삭제하고, 안내 projection에는 맥락 표시용 방 이름·room ID·종료 유형·안내 코드·종료 시각만 둔다. 사용자 문구는 `“{방 이름}” 채팅방이 종료됐어요`를 사용하고 `폐쇄` 표현은 노출하지 않는다.
- Socket은 `moderationRoomCleanupJobs` 단일 listener에서 pending뿐 아니라 이미 completed인 closure job도 처리한다. cleanup이 이벤트 관찰보다 빨리 끝나도 `room:closed`를 놓치지 않고 해당 room socket을 강제 이탈시킨다.
- Phase 3 Production 배포, 실제 운영 방/메시지 삭제 QA와 `firestore:indexes` 전체 원격 구성 반영은 구현 완료와 분리된 별도 승인 게이트다.

## Phase 3.1 방 종료 lifecycle 개편 확정 — 2026-08-10

- 방장 삭제와 관리자 종료 모두 사용자별 신규 안내 문서 대신 하나의 공용 `Rooms/{roomID}` tombstone을 사용한다. 방 콘텐츠·메시지·이미지 경로·Storage는 즉시 삭제하고, 표시 맥락에 필요한 방 이름과 종료 lifecycle만 남긴다.
- 접속 중 참여자는 기존 단일 Socket cleanup-job listener의 `room:closed` 이벤트를 받는다. 확인을 누르면 본인의 member/joinedRooms/roomStates를 정리하고 채팅 화면을 닫는다.
- 오프라인 참여자는 참여중 목록에서 종료된 방을 일반 방과 같은 모양으로 본다. 종료 전용 배지·색·subtitle과 마지막 메시지 위치의 `채팅방 이용이 종료됐어요` 문구는 추가하지 않는다. 해당 행을 선택하면 방 이름과 종료 주체에 맞는 안내를 표시하고 확인 뒤 본인 projection을 정리한다.
- 오프라인 종료 안내의 확인 버튼은 서버 acknowledgement 완료를 기다리지 않고 목록 행을 즉시 제거한다. 같은 세션의 stale 조회는 재삽입하지 않으며 서버 실패 시 행을 복원하고 오류를 표시해 재시도 가능하게 한다.
- 방장 삭제를 수행한 creator는 이미 행위를 인지하므로 안내하지 않고 즉시 membership을 정리한다. 관리자 종료에서는 creator도 일반 참여자처럼 확인 대상이다.
- 확인하지 않은 membership과 공용 tombstone의 최대 보존은 14일이다. 모든 사용자 확인을 기다리지 않고 `moderationRoomCleanupJobs`의 retention phase가 150명 단위, 참여자당 최대 3 writes로 나눠 정리한다.
- tombstone의 `expiresAt`은 Firestore TTL로 room을 먼저 삭제하지 않는다. scheduler due time으로만 사용해 membership projection보다 room이 먼저 사라지는 orphan 상태를 막는다.
- 이미 Production에 존재할 수 있는 `roomClosureNotices` schema v2는 새로 만들지 않는다. 기존 30일 TTL을 유지하고 앱과 새 확인 callable이 임시 호환해 자연 만료시킨다.
- Phase 3.1 구현 완료와 Production Functions·Rules 배포 및 실제 앱 QA는 별도 승인 게이트다.

## 계정 capability 단일 projection과 Storage 조회 한도 — 2026-08-10

- 정상 가입 여부와 계정 삭제 대기 여부는 `users.accountStatus`, 제재 여부는 `moderationAccounts.moderationStatus`에 따로 존재하지만, Rules·Functions·Socket·Storage의 권한 판정은 `moderationAccounts/{uid}` schema v2 한 문서에서 수행한다.
- 계정 삭제 요청·취소와 moderation binding은 `users.accountStatus` 원본과 `moderationAccounts.accountStatus` projection을 같은 transaction에서 갱신한다. projection 누락·구형 schema는 active로 추정하지 않고 fail closed한다.
- 이유는 Storage Rules가 요청 한 건에서 Firestore 문서를 최대 2개만 조회할 수 있기 때문이다. requester의 `users`와 `moderationAccounts`, room까지 세 문서를 조회하던 계약이 정상 이미지 read/upload를 403으로 거부했다.
- 채팅 미디어 read는 requester projection + active room을 읽는다. upload는 Socket이 `createUGC` capability와 room access를 확인해 발급한 짧은 TTL의 서버 전용 pending `MediaUploads/{messageID}` reservation + active room만 Storage Rules가 읽고, sender·kind·path prefix·expiry가 일치할 때만 허용한다. 별도 완화 규칙이나 클라이언트 생성 reservation은 허용하지 않는다.
- 방 ID collection-group 단일 필드 index는 추가하지 않는다. 운영 QA 검증 스크립트의 조회 편의를 위한 index는 제품 query 계약이 아니며, direct path 검증으로 충분하다.

## 텍스트 표현 자유와 현재 규모의 기술적 전송 남용 방어 — 2026-08-18

- 채팅 메시지·룩북 공유 텍스트·댓글·답글의 의미를 자동 판정하지 않는다. 욕설·혐오·위협·금칙어, 공백·기호·Unicode 우회, 광고성 문구·URL과 동일 문장 반복을 자동 차단하지 않으며 생성형 AI나 외부 text moderation API도 사용하지 않는다.
- 부적절하거나 불편한 표현은 사용자 신고·차단, 방 생성자의 내보내기/재입장 제한과 플랫폼 관리자의 문맥 기반 사후 검토·제재로 처리한다. 신고 aggregate의 전체 사건 수·고유 신고자 수·사유·최초/최근 신고 시각·검토 상태와 과거 제재 이력은 운영 우선순위에 사용하되 신고 횟수만으로 자동 제재하지 않는다.
- 댓글·답글은 현재 텍스트 전용이며 생성 API가 `attachments: []`만 기록한다. 따라서 채팅과 같은 신고·사용자 차단·관리자 사후 검수 모델을 사용한다. 댓글·답글 이미지/동영상 기능은 Phase 6 범위가 아니며 향후 추가 시 미디어 수집·evidence 계약을 별도로 설계한다.
- 텍스트 서버 경계는 콘텐츠 의미와 무관한 타입·빈 문자열·식별자·권한·최대 길이만 검증한다. 현재 채팅/룩북 공유 텍스트 UTF-8 4,000 bytes와 trim 이후 댓글·답글 UTF-16 code unit 1,000 상한을 유지한다.
- 최대 길이는 기술적 payload·메모리·저장 비용 보호 장치다. 앱에 길이 counter나 제한 임박 경고는 표시하지 않고 상한을 넘는 입력 자체를 반영하지 않는다. 서버도 같은 상한을 검증하며, 서버 거부 시 입력 원문은 유지해 사용자가 수정·재시도할 수 있게 한다. 채팅은 서버와 같은 UTF-8 bytes, 댓글·답글은 Swift `message.utf16.count`로 계산한다.
- rate limit은 표현 정책이나 광고/반복 판정이 아니라 자동화 공격과 Firestore write·Socket broadcast·FCM fan-out 과부하를 막는 기술적 최후 방어선이다.
- 현재 Socket는 단일 인스턴스와 프로세스 메모리 limiter를 유지한다. text 12/2초, lookbook share 6/2초, image preflight/finalize 각 4/2초, video preflight/finalize 각 4/2초의 기존 상한을 유지하며 key는 `moderationPrincipalID + roomID + messageKind`로 통일한다.
- canonical principal binding이 없거나 유효하지 않은 Socket 연결은 auth/capability 경계에서 fail closed한다. `socket.id`, 클라이언트 제출 UID와 이메일로 대체하지 않는다. 구현 전에 Development·Production active account의 principal projection 누락을 읽기 전용으로 감사한다.
- 유효한 `messageID`를 limiter보다 먼저 확정하고 같은 process·같은 messageID 재시도는 quota를 다시 소비하지 않는다. 이를 위해 bucket이 짧은 window 동안 최근 계산한 message ID를 함께 기억하며, 정상 경로에 클라이언트 왕복이나 Firestore read를 추가하지 않는다. 기존 Firestore transaction의 message 존재 확인이 최종 멱등성 원장이다.
- 메모리 bucket은 60초 idle TTL, 30초 bounded sweep, 최대 50,000 active bucket으로 제한한다. 한도 도달 시 새 bucket 생성은 fail closed하고 최소 metadata metric/경고를 남긴다. 배포·재시작으로 짧은 limiter 상태가 초기화되는 것은 단일 인스턴스 현재 규모에서 수용하며 메시지 원장에는 영향이 없다.
- 댓글·답글은 같은 canonical principal 기준 전역 합산 UTC 1분 20건의 burst guard를 둔다. Functions가 다중 인스턴스일 수 있으므로 프로세스 메모리가 아니라 server-only Firestore minute bucket transaction을 사용한다. comment document ID는 post 경로 안에서 `SHA-256(moderationPrincipalID + ":" + operation + ":" + clientRequestID)`로 결정한다. 같은 요청의 기존 문서가 author·parent·message와 일치하면 기존 commentID와 현재 count projection을 반환하고 quota를 다시 소비하지 않으며, 불일치하면 `IDEMPOTENCY_CONFLICT`다. counter에는 본문·대상 상세를 저장하지 않고 2일 TTL로 정리한다.
- 앱은 전송 탭마다 UUID `clientRequestID`를 만들고 네트워크 재시도 동안 같은 ID를 유지한다. 사용자가 입력을 수정·취소하거나 전송이 완료된 뒤 새 글을 작성하면 새 ID를 만든다. rate limit은 자동 재전송하지 않고 입력을 유지한 채 `잠시 후 다시 시도해주세요`를 안내하며 `retryAt` 이후 사용자가 직접 재전송한다.
- Cloud Run `max-instances=1`은 Socket Phase 6 배포 계약이다. Redis/Memorystore는 현재 도입하지 않는다. Socket를 2개 이상 인스턴스로 전환하거나 단일 인스턴스의 연결 수·CPU·메모리·latency 한계, 실제 프로세스 간 limiter 불일치 또는 abuse가 관측될 때 Socket.IO adapter/PubSub와 공유 limiter를 별도 keyspace·TTL로 도입한다. 대규모 단계에서는 메시지 ordering은 roomID, abuse limiter는 moderationPrincipalID 기준 sharding을 검토하며 Firestore를 durable source로 유지한다.
- 신규 메시지부터 `senderEmail`을 Firestore message, Socket payload, FCM data payload, 앱 `ChatMessage`와 GRDB에 저장·전송하지 않는다. 클라이언트가 제출한 email은 무시한다. 아직 외부 배포 전이므로 구버전 호환은 두지 않으며, 구현 전 active message 데이터를 읽기 전용 감사해 사실상 비어 있으면 migration을 만들지 않는다.
- 정상 메시지는 기능상 필요한 Firestore 메시지 원장에만 저장한다. Socket 성공/유효성 실패 로그에 메시지·답장 원문, 이메일, nickname/avatar 등 payload 전체를 복제하지 않고 event, 안정된 오류 코드, message ID, seq, payload bytes, 처리 시간처럼 진단에 필요한 최소 metadata만 기록한다. 내부 QA로 이미 쌓인 과거 Cloud Logging 원문은 소급 삭제하지 않고 기존 retention으로 자연 만료시키며 신규 sink/export를 만들지 않는다.
- 신고된 텍스트만 기존 Phase 2 계약의 제한된 서버 전용 snapshot으로 보존하고, 관리자는 신고 처리 목적과 권한 안에서 확인한다.
- Phase 6 관리자 queue는 기존 `reviewState → priorityClass → slaDueAt → lastReportedAt` 고정 정렬을 유지한다. 신고 수·고유 신고자 수·과거 제재 이력의 임의 정렬과 sanction-history projection은 후속 `admin-web-operations-migration`에서 설계한다.
- 이미지·동영상도 텍스트와 동일하게 외부 의미 판정 provider로 보내지 않고 신고·관리자 사후 검수로 관리한다. Phase 7의 전용 Cloud Run은 유해성 판정기가 아니라 quarantine 객체의 실제 형식·크기·codec·track·해상도 검증, metadata 제거와 공개 객체 정규화를 담당한다.

## Phase 7 미디어 수집·신고 evidence·가시성

- 흐름은 `reservation → quarantine upload → technical validation/metadata removal → ready`다. ready 전에는 message document·room `seq`·Socket·FCM·preview·다른 사용자의 Storage read가 없고, ready transaction에서만 공개 객체와 message/seq를 한 번 생성한다.
- 이미지 선택기는 선택 수를 제한하지 않되 앱이 최대 30장씩 메시지로 분할한다. 한 이미지의 quarantine `source` 상한은 15 MiB, 메시지의 source 합산 상한은 150 MiB, 긴 변은 최대 4096px로 둔다.
- iOS는 Photos/카메라 원본 byte를 그대로 올리지 않고 업로드 전용 `source`를 만든다. 정적 이미지는 방향을 실제 pixel에 bake하고 긴 변 4096px·sRGB로 맞추며 불필요 metadata를 제거한다. HEIC/HEIF와 JPEG는 JPEG quality 0.92로 인코딩하고, 투명 PNG와 초기 비투명 PNG는 PNG를 보존한다. 이 1차 정규화는 전송량·quarantine 용량·worker 다운로드/처리량을 줄이기 위한 것이며 서버의 기술 검증과 최종 `display/thumbnail` 생성을 대체하지 않는다.
- 사용자는 JPEG·HEIC·PNG와 GIF를 선택할 수 있다. iOS는 정적 HEIC/HEIF만 위 JPEG 계약으로 바꾸고 GIF는 frame/order/delay/loop를 유지한 채 허용 용량 안의 animated GIF source로 올린다. 서버 transport는 JPEG·PNG·animated GIF만 허용하며 raw HEIC/HEIF는 `unsupportedMedia`로 거부한다. Phase 7.0 Linux fixture로 static 64M pixel, GIF 200 frame·frame당 16,777,216 pixel·총 100M decoded pixel, 이미지당 60초를 확정했다. Cloud Run Job은 2 vCPU·1 GiB에서 첨부를 순차 처리하며 GIF 지원 자체는 유지한다.
- 동영상은 iOS가 720p H.264/AAC MP4 업로드 source를 준비한다. 메시지당 1개·source와 서버 결과 모두 최대 350 MiB를 유지하고 재생 시간 상한은 두지 않는다. source 전체를 attachment 전용 V4 signed PUT URL 하나로 foreground `URLSession`에서 quarantine에 직접 올린다. 전송 중 pending UI용 local thumbnail은 서버로 올리지 않으며, worker가 `min(1초, duration/2)` 시점에서 긴 변 512px JPEG 공개 thumbnail을 생성한다. thumbnail 추출 실패는 `invalidMedia`로 수렴한다. 실제 MIME·codec·duration·audio/video track·회전·색상 정보는 서버 검증값을 권위로 사용한다.
- 이미지에서는 GPS, 촬영 시각, 기기·카메라·렌즈·일련번호·소유자·software·MakerNote·XMP/IPTC·편집 이력·얼굴 영역·embedded thumbnail·unique ID·원본 파일명·depth/portrait·Live Photo 연결 등 불필요 metadata를 제거한다. 동영상에서도 위치·시각·기기·제목·comment·QuickTime location·불필요 metadata와 보조 track을 제거한다. 사용자의 로컬 원본은 변경하지 않는다.
- 업로드 상태는 `uploading → queued → processing → ready`, 종료 상태는 `canceled | failed | expired`다. 발신자는 ready 전 취소할 수 있고 최초 server transaction commit이 이긴다. 기술 오류는 서버가 최대 3회 재시도한 뒤 사용자 수동 재시도로 전환하며, 실패한 로컬 outbox 원본은 7일 뒤 자동 삭제한다.
- 신고 성공만으로 개인 숨김을 만들지 않는다. 추후 사용자가 명시적으로 `이 메시지 숨기기`를 선택하면 전체 메시지를 개인 숨김하며, 사용자 차단은 기존 전역 차단 관계로 별도 처리한다.
- 전역 임시 비노출은 관리자 수동 조치 또는 같은 `reviewRevision`에서 24시간 이내 서로 다른 canonical principal의 긴급 사유 2명이나 전체 사유 합계 3명에 도달할 때 적용한다. 자동 제재는 하지 않으며 관리자가 evidence를 확인한 뒤 콘텐츠 결정과 계정 조치를 각각 명시적으로 선택한다.
- 전역 비노출 메시지는 동일 seq를 유지하며 `검토 중인 메시지입니다` tombstone으로 보이고 공개 media 접근·room preview·앱 내부 cache를 정리한다. 기각 시 같은 messageID/seq의 내용을 복원하되 새 push·banner·latestSeq·read frontier rollback·인위적 unread를 만들지 않는다. 위반 확정 시 기존 seq를 삭제 tombstone으로 전환한다. 기각 전 신고 수가 다음 revision을 즉시 재비노출시키지 않는다.
- 신고와 삭제는 server-only `moderationMessageGuards/{incidentID}`를 함께 읽고 쓰는 transaction으로 first-commit-wins를 보장한다. Firestore client가 읽는 message document에는 신고 여부나 evidence hold를 노출하는 server-only 필드를 넣지 않는다.
- 삭제가 먼저 commit되면 신고 문서·aggregate·evidence·moderation count를 만들지 않고 `messageAlreadyDeleted`와 messageID/seq를 반환한다. 다만 이전에 보지 못한 `clientRequestID`의 최상위 transport receipt와 공유 limiter slot 1개는 만들며, 앱은 `이미 삭제된 메시지예요`를 표시하고 같은 messageID/seq를 즉시 삭제 tombstone으로 갱신한다.
- 신고 준비가 먼저 commit되면 server-only guard와 evidence hold/copy job만 만들고 이후 삭제는 화면상 tombstone을 즉시 적용하되 Storage cleanup을 `awaitingEvidence`에서 기다린다. evidence copy 완료 뒤에만 신고를 `accepted`로 확정하고 guard를 `available`로 바꿔 cleanup을 재개한다. copy가 확정 실패하면 신고 집계 없이 `failed`로 끝내고 hold를 해제해 원본 cleanup을 재개한다.
- open/inReview evidence는 결정까지 보존하고 24시간 긴급·72시간 일반 운영 SLO로 장기 미처리를 감시한다. 기각·콘텐츠 삭제만·경고만이면 결정 transaction 직후 비동기 삭제를 enqueue한다. 계정 일시 제한·영구 정지 근거 evidence는 30일 이의제기 기간 동안 보존하고, 기간 내 이의제기가 있으면 해결 직후 삭제하며 없으면 30일에 삭제한다. legal hold는 명시적이고 감사 가능한 법적 절차에만 사용한다.
- 저장 영역은 환경별 quarantine·일반 media·moderation evidence의 3개 bucket 경계로 분리한다. quarantine은 `asia-northeast3` Standard, soft delete·versioning off, 1일 lifecycle이다. source는 ready commit 성공, 취소, 최종 실패 또는 만료가 확정되면 즉시 영구 삭제하고 1일 lifecycle은 crash·IAM/네트워크 오류·cleanup 버그로 즉시 삭제를 놓친 객체만 정리하는 안전망이다. 일반 media에는 새로 만든 `display`와 `thumbnail`만 두고 evidence에는 신고된 메시지의 정규화 `display` 전체를 복사한다.
- `MediaUploads`와 processing은 항상 1:1이므로 별도 processing 문서를 만들지 않는다. `MediaUploads`가 예약, attachment별 단일 signed PUT target/source generation, 상태, attempt, lease, execution, retry와 normalized manifest를 통합 소유한다. 업로드 예약과 signed URL은 24시간이며 processing deadline 6시간은 finalize가 source 검증을 완료해 `queued`로 전환한 시점부터 계산한다. terminal 뒤에는 바이너리나 실행 lease가 아니라 `clientMutationID`와 최소 결과만 7일 보존해 응답 유실·앱 재실행의 같은 요청에 기존 결과를 반환하고 중복 메시지·재처리를 막은 뒤 TTL 삭제한다.

- 이미지와 영상 source는 attachment당 일반 V4 signed PUT 하나로 quarantine에 직접 올린다. URL 만료 또는 전송 실패 시 서버는 고정 path의 객체 generation·크기·체크섬을 한 번 확인해 정상 객체면 성공으로 복구하고, 아니면 로컬 실패로 전환한다. 사용자는 보호된 local source에서 새 예약으로 재시도하거나 삭제한다. create는 `ifGenerationMatch=0`이고 성공·취소·최종 실패에는 source를 즉시 정리하며 1일 bucket lifecycle은 cleanup 실패 안전망으로만 사용한다.
- 이미지·영상 queue와 고정 실행 slot을 분리한다. Development는 이미지 1·영상 1, Production 초기값은 이미지 4·영상 1이다. dispatcher가 slot을 획득한 경우 이미지는 private Cloud Run Service를 호출하고 영상은 Cloud Run Job을 시작한다. 둘 다 2 vCPU·1 GiB, retry 0이며 이미지 Service는 min instance 0·concurrency 1, 영상 Job timeout은 12분이다.
- 업로드 중 사용자 취소 UI는 제거한다. 앱 종료·방 이탈·네트워크 단절은 클라이언트 전송 실패로 수렴시키고 서버 예약·격리 객체의 cancel/TTL cleanup 계약은 운영 안전망으로 유지한다. 로컬 실패 메시지는 재시도/삭제 두 동작을 제공한다.
- principal별 active 업로드는 server-only 고정 slot 문서로 이미지 메시지 2개·영상 1개를 transaction 점유한다. 이는 누적·일일 전송량이 아니라 `uploading|queued|processing` 동시 처리 상한이다. 이미지 메시지 하나가 최대 30장이므로 동시에 최대 60장을 점유할 수 있지만 ready/canceled/final failed/expired 즉시 slot을 반환하고 앱의 local queue가 다음 30장 묶음을 순차 시작하므로 총 전송 장수는 제한하지 않는다. 같은 `clientMutationID` 재시도는 slot을 추가 소비하지 않는다. 이 backpressure는 한 principal의 queue 독점, 앱 버그와 악의적 대량 업로드로 인한 Cloud Run·Storage 비용 폭주를 제한한다. 24시간 byte hard cap은 초기 확정하지 않고 실제 사용량·abuse·비용 지표를 근거로 별도 결정한다.
- iOS local queue는 `ChatContainer`가 공유하는 `ChatMediaUploadUseCase` 내부 actor가 canonical principal의 media kind별 FIFO로 소유한다. 이미지와 영상은 server principal slot이 분리되어 있으므로 서로 다른 lane을 사용하되 각 기기에서는 kind별 한 메시지만 reservation부터 terminal까지 실행한다. 서버 이미지 2·영상 1 slot은 다른 기기·세션과 stale lease까지 포함한 최종 권위이며 로컬 queue가 이를 대체하지 않는다.
- `chat:mediaPreflight`의 `active_upload_limit`은 terminal 실패가 아니라 slot 대기 신호다. FIFO head는 새 identity를 만들지 않고 같은 `uploadID`·`clientMutationID`로 2·4·8·15·30초 뒤 재시도하고 이후 30초 간격을 유지한다. 대기 중에는 signed URL과 server reservation이 없고 보호된 source·outbox·pending 버블만 유지한다. permission/ban/not-found/invalid contract와 같은 비용량 오류는 즉시 실패한다.
- local turn은 server `ready|canceled|failed|expired` 또는 reservation 이후 실패의 best-effort cancel 수렴 뒤 반환한다. 앱 종료·방 이탈은 기존 foreground 계약대로 active와 waiting task를 취소하고 자동 background 전송하지 않으며, 보존된 source/outbox에서 수동 재시도 가능한 실패 상태로 전환한다. 서버 wait 문서·scheduler·signed URL 선발급은 Phase 7.3에 추가하지 않는다.
- 앱 재실행 복원은 foreground 파일 PUT을 자동으로 다시 시작하지 않는다. 로컬 outbox bubble은 네트워크 상태 조회 전에 silent pending으로 먼저 복원해 영속화용 `isFailed`가 왼쪽 실패 표시로 깜빡이지 않게 한다. 서버가 이미 `queued|processing|ready`면 기존 server lifecycle만 모니터링하고, `uploading`이면 finalize in-flight 경합을 위해 2·4·8초 동안 같은 identity의 status만 재조회한다. 계속 `uploading`이면 cancel 후 수동 재시도·삭제 상태로 전환하며, 조회 오류가 반복돼도 자동 PUT 없이 수동 복구로 닫는다. 종료 직전 finalize와 cancel의 first-commit-wins 결과가 `ready`면 성공을 우선한다.
- 일반 이미지·동영상 전송 실패는 별도 팝업을 표시하지 않고 실패 버블의 재시도·삭제 액션으로만 복구한다. 전송 실패 뒤 room access 재확인 결과 ban인 경우에는 사용자가 전송 중단 원인을 알아야 하므로 `채팅방 참여가 제한되어 전송을 중단했어요.` 안내를 유지한다.

## 플랫폼 총관리자와 관리자 웹

- 관리자 웹은 Firebase Auth ID token으로 서버 API를 호출하고 service account JSON, Admin SDK credential 또는 장기 비밀키를 브라우저에 포함하지 않는다.
- 최초 `platformAdmins` bootstrap과 권한 부여·회수는 별도 audited CLI 또는 동등한 서버 전용 운영 경계에서 수행한다.
- 관리자 action은 actor UID, 이전 상태, 새 상태, reason code, 관련 report ID, 시각을 서버 전용 audit에 남긴다.
- 같은 신고를 여러 관리자가 처리할 때 `caseVersion` 기반 optimistic concurrency를 적용하고 stale mutation을 거부한다.
- 관리자 자신 또는 다른 플랫폼 총관리자에 대한 제재 가능 여부와 break-glass 복구 절차는 관리자 운영 runbook에서 명시한다.
- 관리자 웹이 닫혀 있어도 신고 접수, 차단, 제재 enforce와 자동 만료 판정은 계속 동작한다. 외부 출시 시점에는 웹 완성 여부와 무관하게 Phase 2 관리자 API 또는 제한된 운영 도구로 실제 신고를 확인·처리할 담당자와 긴급 24시간/일반 72시간 내부 경고 경로가 준비돼야 한다.

## 예상 구현 경계

- iOS View/Coordinator: 메시지·사용자·방 신고 진입, 전역 차단·해제, 자기 메시지 삭제, 방 생성자의 메시지 삭제·사용자 내보내기·ban 해제, 제한/정지 안내, 고객지원 route
- iOS ViewModel/UseCase: 신고·차단·삭제·내보내기 intent와 화면 상태, 차단 메시지 visibility policy, 제재 capability 판정
- iOS Repository/Store: Functions API, 전역 block 상태, moderation projection, Socket/GRDB visibility 접합부
- Functions: 신고 submission·aggregate, 메시지 서버 삭제, block mutation, moderation subject HMAC, room ban, 플랫폼 제재·해제·audit, owner succession, 고객지원/관리자 query API
- Socket: moderation capability와 room ban 검증, 차단 push 제외, principal 기반 기술적 burst 제한, 텍스트 payload 로그 최소화, 미디어 reservation/기술 검증 후 ready, 즉시 퇴장·계정 비활성 disconnect
- Firestore/Storage Rules: report·aggregate·audit·moderation subject·ban의 클라이언트 직접 write 차단, 메시지 direct mutation 차단, 제재 capability와 room ban read/join 경계, 격리/ready Storage 분리
- 관리자 웹 연계: 보류/검토 필요/긴급 message incident, 사용자·방 aggregate, 고유 신고자/사유·반복 메시지·확정 경고 집계, 처리 결과, 메시지 삭제와 사용자 제재 UI. 실제 권한 검증과 데이터 변경은 서버 API가 담당한다.
- DI/조립: ChatContainer와 CompositionRoot가 신고·차단·삭제 UseCase/Repository/visibility policy를 주입하고, 화면 전환은 ChatCoordinator가 연결한다. `ChatViewController`에 Firebase/Functions/Socket 구현을 직접 추가하지 않는다.

## 피해야 할 설계

- 메시지마다 독립적으로 열고 닫는 case를 만들어 사용자 단위 반복 abuse 신호와 분리하는 설계. 메시지 incident와 작성자 aggregate는 함께 기록한다.
- 신고 횟수를 관리자 확정 경고로 간주하거나 횟수만으로 계정을 자동 제한·정지하는 설계
- 이메일, Firebase UID 또는 클라이언트가 제출한 provider ID를 장기 제재 subject로 사용하는 설계
- 차단 관계를 별도 채팅 collection으로 중복 저장하거나 양쪽 공동방 메시지를 모두 숨기는 설계
- 차단 메시지를 숨기면서 realtime seq까지 버려 gap recovery가 반복되는 설계
- room ban 사용자가 비참여 preview 또는 새 UID로 같은 방을 계속 읽고 재가입하는 설계
- Firebase Auth disable만으로 일시 제한·영구 정지를 구현해 신고·계정 삭제·지원 경로까지 잃는 설계
- 미디어 기술 검증·정규화 완료 전 메시지를 broadcast/push하거나 공개 Storage에서 읽게 하는 설계
- 관리자 웹에 service account credential을 넣거나 localhost 여부로 권한을 부여하는 설계
- HMAC 원장을 완전한 익명정보로 간주해 보존 목적·기간·접근 권한을 고지하지 않는 설계

## 구현 계획과 운영 출시 전 필수 확인 조건

- exact API·데이터·index·오류·idempotency 계약, 변경 파일, migration과 자동·수동 검증 순서는 `plan.md`의 Phase 0 계약부터 고정한다.
- 관리자 웹 화면 구현은 별도 `admin-web-operations-migration` 작업이 담당한다. 이 작업은 웹이 사용할 신고 조회·처리·제재 서버 API와 감사 계약까지 제공한다.
- 방 관리자 임명은 별도 `chat-room-moderator-delegation` 작업이 담당한다. 이 작업은 생성자만 허용하는 공통 room moderation authorization 경계를 제공한다.
- 구현을 시작하기 전에는 별도 사용자 승인을 받는다. Production 출시 전에는 아래 외부·운영 조건을 모두 확인한다.
  - 계정 삭제 후 moderation principal과 room ban 원장을 보존할 법적 근거·기간·고지 또는 동의
  - Google·Apple·Kakao 인증 경계의 provider subject 확보와 Kakao `User ID Fixed` 재연결 QA
  - 미성년자 이용 범위, 성적·불법 콘텐츠 발견 시 운영 escalation과 최신 App Store 연령 등급 응답
  - 고객지원 URL·연락처, 긴급·일반 신고 분류와 실제 담당 운영 경로
  - 신고 evidence 처리·접근·보존 고지, App Privacy 응답과 Development 미디어 형식/metadata/GIF/장시간 동영상 fixture 통과

## 구현 후 검증 기준

- 작성자/room moderator/일반 사용자별 메시지 삭제 권한과 direct Firestore write 거부
- 신고 API idempotency, 사용자 aggregate 집계, 방 신고와 관리자 동시 처리 충돌
- 차단 직후 현재 화면·검색·gallery·reply preview·room preview·Socket/banner/push에서 대상 콘텐츠 비노출, 해제 후 복원
- hidden message seq를 소비하면서 strict ordering과 gap recovery가 유지되는지 검증
- room ban의 membership/projection/count/Socket/push/read 원자 수렴과 동일 provider 재가입 차단
- 일시 제한·영구 정지의 Rules/Functions/Socket/Storage capability 일치와 안전 action·계정 삭제 접근 보존
- 수동 방장 탈퇴, 계정 삭제·영구 정지 successor 선택과 적격자 없음 폐쇄
- 텍스트 타입·빈 값·최대 길이, principal 기반 rate limit의 reconnect/다중 연결 우회와 원문 로그 비노출
- 미디어 격리, 기술 검증 완료 전 비노출, 신고 threshold·복원, retry/cancel/cleanup과 형식·resource fixture
- platform admin 인증, 최근 재인증, audit, stale caseVersion 거부와 service account credential 비노출
- App Review용 일반 사용자 2개, 방 생성자 1개, 플랫폼 총관리자 1개의 Development demo 계정과 신고·차단·방 내보내기·제재 복구·고객지원 경로
