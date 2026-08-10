# Platform Admin Operations

## 목적

`platformAdmins/{uid}` 최초 등록·회수와 권한 사고 복구를 Firebase Console 수동 편집이 아닌 audited CLI로 수행한다. CLI 출력에는 UID·email·provider subject를 포함하지 않는다.

## 진입점

- CLI: `functions/scripts/manage-platform-admin.mjs`
- gate: `functions/src/moderation/admin/platformAdminOperations.ts`
- 권한 검증: `functions/src/moderation/admin/service.ts`
- contract: `contracts/chat-moderation-v1.json`

## 사전 조건

- 실행 project는 `outpick-test` 또는 `outpick-664ae`여야 한다.
- 선택 provider의 Firebase Auth 계정이 정확히 1명이어야 한다.
- 대상은 `users.accountStatus=active`, `moderationAccounts.moderationStatus=active`이고 canonical principal이 있어야 한다.
- Production apply는 전체 Auth 예상 건수, provider 예상 건수와 exact confirmation을 모두 요구한다.

## 식별정보 비노출 감사

```bash
cd functions
node scripts/manage-platform-admin.mjs \
  --project outpick-664ae \
  --action audit
```

출력은 provider별 Auth·eligible·brand admin·platform admin 건수만 포함한다.

## Production 등록

```bash
cd functions
node scripts/manage-platform-admin.mjs \
  --project outpick-664ae \
  --action grant \
  --provider kakao \
  --apply \
  --expected-auth-count 2 \
  --expected-provider-count 1 \
  --confirm-production GRANT_SINGLE_PLATFORM_ADMIN_TO_OUTPICK_664AE
```

같은 명령의 재실행은 `changed:false`로 수렴한다. 대상 document는 schemaVersion, isActive, createdAt, updatedAt, revokedAt만 가진다.

## Production 회수

```bash
cd functions
node scripts/manage-platform-admin.mjs \
  --project outpick-664ae \
  --action revoke \
  --provider kakao \
  --apply \
  --expected-auth-count 2 \
  --expected-provider-count 1 \
  --confirm-production REVOKE_SINGLE_PLATFORM_ADMIN_FROM_OUTPICK_664AE
```

회수는 문서를 삭제하지 않고 `isActive=false`, `revokedAt=server timestamp`로 남긴다.

## Break-glass

- 앱이나 관리자 callable로 자기 자신 또는 active platform admin을 제재할 수 없다.
- active platform admin이 0명이 되어도 위 CLI는 Firebase/GCP 운영자 ADC로 실행할 수 있다.
- provider가 여러 명이거나 전체 Auth 예상 건수가 바뀌면 apply를 중단한다. 이 경우 대상 식별 방식과 기대 건수를 다시 승인받고 CLI 계약을 갱신한다.
- 복구 뒤 `audit`으로 active platform admin 1명인지 확인하고, 관리자 callable은 5분 이내 재인증 토큰으로 smoke한다.
