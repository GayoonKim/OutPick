# Lookbook Extraction Issue Operations CLI

Firestore에 직접 접근하지 않고 IAM으로 보호된 운영 API를 호출하는 내부 CLI다.

## 전제 조건

- Google Cloud CLI에 개발자 계정으로 로그인되어 있어야 한다.
- 해당 계정은 환경별 operator service account의 `roles/iam.serviceAccountTokenCreator`를 가져야 한다.
- operator service account는 대상 Cloud Run service의 `roles/run.invoker`를 가져야 한다.
- endpoint, project, region, operator는 `src/config.js`의 고정 allowlist만 사용한다.

## 예시

```bash
cd tools/lookbook-extraction-issue-ops
npm test
node src/index.js list --environment development
node src/index.js show --environment development --fingerprint <40-char-fingerprint>
node src/index.js show-batch --environment development \
  --fingerprint <fingerprint-1> --fingerprint <fingerprint-2>
node src/index.js start --environment development \
  --fingerprint <fingerprint> --expected-state-version 1
```

Production fix 검증은 target runtime과 배포 revision/source revision을 모두 명시한다. verifier가 대표 job URL을 서버 내부에서 읽으므로 URL이나 smoke run ID는 입력하지 않는다.

```bash
node src/index.js verify-fix --environment production \
  --fingerprint <fingerprint> --expected-state-version <version> \
  --stage seasonImageImport --target-runtime-version extractor:1.3.0 \
  --worker-revision <revision> --worker-source-revision <git-sha> \
  --confirm-production outpick-664ae
```

Production write는 추가로 `--confirm-production outpick-664ae`가 필요하지만, 이 확인값은 IAM이나 배포 승인을 대신하지 않는다.

상세 운영·배포 절차는 `docs/ai/runbooks/LOOKBOOK_EXTRACTION_ISSUE_OPERATIONS.md`를 따른다.
