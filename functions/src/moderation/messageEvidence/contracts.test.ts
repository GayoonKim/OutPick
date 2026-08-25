/* eslint-disable max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {
  MESSAGE_AUTHOR_PATTERN_WINDOW_MILLIS,
  MESSAGE_GLOBAL_VISIBILITY_WINDOW_MILLIS,
  MESSAGE_SANCTION_APPEAL_RETENTION_MILLIS,
  canTransitionMessageEvidence,
  canTransitionMessageEvidenceCleanupJob,
  canTransitionMessageEvidenceJob,
  createsAcceptedMessageReportEffects,
  isMessageEvidenceCleanupDue,
  messageAuthorPatternEvaluation,
  messageEvidenceBundleID,
  messageEvidenceCleanupJobID,
  messageEvidenceCopyJobID,
  messageEvidenceObjectPath,
  messageEvidenceRetryDelayMillis,
  messageEvidenceRetention,
  messageGlobalVisibilityEvaluation,
  messageGuardID,
  messageIncidentID,
  messageReportPreparationID,
  messageReportRequestID,
  messageReporterID,
  messageReportStatusForEvidence,
  messageReportSubmissionID,
  messageReviewRevisionID,
  nextMessageQueueClass,
  nextMessageReviewRevision,
} from "./contracts.js";

test("message evidence ID는 versioned canonical tuple로 결정되고 domain별로 분리된다", () => {
  const incident = messageIncidentID("room:a", "message:b");
  assert.equal(incident, messageIncidentID("room:a", "message:b"));
  assert.notEqual(incident, messageIncidentID("room", "a:message:b"));
  assert.match(incident, /^[a-f0-9]{64}$/);
  assert.equal(messageGuardID(incident), incident);
  assert.notEqual(messageReporterID("principal-1"), messageReporterID("principal-2"));

  const preparation = messageReportPreparationID({
    incidentID: incident,
    reviewRevision: 0,
    reporterModerationPrincipalID: "principal-1",
  });
  const submission = messageReportSubmissionID({
    incidentID: incident,
    reviewRevision: 0,
    reporterModerationPrincipalID: "principal-1",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
  });
  const request = messageReportRequestID({
    incidentID: incident,
    reporterModerationPrincipalID: "principal-1",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
  });
  const bundle = messageEvidenceBundleID(incident, 0);
  assert.notEqual(preparation, submission);
  assert.notEqual(request, submission);
  assert.equal(request, messageReportRequestID({
    incidentID: incident,
    reporterModerationPrincipalID: "principal-1",
    clientRequestID: "123e4567-e89b-42d3-a456-426614174000",
  }));
  assert.notEqual(bundle, preparation);
  const copyJob = messageEvidenceCopyJobID(bundle);
  const cleanupJob = messageEvidenceCleanupJobID(bundle);
  assert.notEqual(copyJob, cleanupJob);
  assert.deepEqual({incident, preparation, submission, request, bundle, copyJob, cleanupJob}, {
    incident: "872cc02891649c6ac6359413fc3441eb4f60593aa81e8fe6e73d497c640b5728",
    preparation: "8dd3e21c5255e4b25ee6a3b203799f5c493f98eccc89a2348a199e34501a1b23",
    submission: "69206506a709febc3ee0e6887637bab68ab7866708aa78edd24c98fa2df70a6d",
    request: "479c10f24af8108bf0a85a4da64fc18c0a8245c4a5825315230fd7dfe69ac5b6",
    bundle: "c54945a8a57c8ce018773da50470728e717c364d1355f36d74a1e8e4ea107128",
    copyJob: "5b384339fcdace55405f84427227a37dbddb801a3465f26cf4f24c67314174df",
    cleanupJob: "37a32e30f48a2e99764fcb7faeef180a6470ad70f57548df0123d83bad97f917",
  });
});

test("evidence object path는 실패 재시작 generation을 물리적으로 분리한다", () => {
  assert.equal(
    messageEvidenceObjectPath({bundleID: "bundle", attemptGeneration: 0, attachmentID: "image"}),
    "bundle/g0/image/display",
  );
  assert.equal(
    messageEvidenceObjectPath({bundleID: "bundle", attemptGeneration: 1, attachmentID: "image"}),
    "bundle/g1/image/display",
  );
  assert.throws(() => messageEvidenceObjectPath({bundleID: "bad/path", attemptGeneration: 0, attachmentID: "image"}));
});

test("evidence copy는 최초 포함 3회이며 두 retry는 1분과 2분이다", () => {
  assert.equal(messageEvidenceRetryDelayMillis(1), 60_000);
  assert.equal(messageEvidenceRetryDelayMillis(2), 120_000);
  assert.throws(() => messageEvidenceRetryDelayMillis(3));
});

test("review revision은 0에서 시작하고 terminal review 뒤에만 증가한다", () => {
  assert.equal(messageReviewRevisionID(0), "r0");
  assert.equal(nextMessageReviewRevision({
    exists: false,
    reviewState: "open",
    reviewRevision: 7,
  }), 0);
  assert.equal(nextMessageReviewRevision({
    exists: true,
    reviewState: "inReview",
    reviewRevision: 2,
  }), 2);
  assert.equal(nextMessageReviewRevision({
    exists: true,
    reviewState: "dismissed",
    reviewRevision: 2,
  }), 3);
});

test("evidence available 뒤에만 신규 accepted 신고 효과를 만든다", () => {
  assert.equal(messageReportStatusForEvidence("copyPending"), "processing");
  assert.equal(messageReportStatusForEvidence("copying"), "processing");
  assert.equal(messageReportStatusForEvidence("available"), "accepted");
  assert.equal(messageReportStatusForEvidence("failed"), "failed");
  assert.equal(createsAcceptedMessageReportEffects("processing"), false);
  assert.equal(createsAcceptedMessageReportEffects("failed"), false);
  assert.equal(createsAcceptedMessageReportEffects("alreadyReported"), false);
  assert.equal(createsAcceptedMessageReportEffects("accepted"), true);
});

test("queue는 holding에서 reviewRequired와 urgent로만 승격하고 강등하지 않는다", () => {
  assert.equal(nextMessageQueueClass({
    currentQueueClass: null,
    reason: "spam",
    distinctAcceptedReporterCount: 1,
  }), "holding");
  assert.equal(nextMessageQueueClass({
    currentQueueClass: "holding",
    reason: "harassment",
    distinctAcceptedReporterCount: 2,
  }), "reviewRequired");
  assert.equal(nextMessageQueueClass({
    currentQueueClass: "holding",
    reason: "privacy",
    distinctAcceptedReporterCount: 1,
  }), "urgent");
  assert.equal(nextMessageQueueClass({
    currentQueueClass: "urgent",
    reason: "spam",
    distinctAcceptedReporterCount: 3,
  }), "urgent");
});

test("24시간 시작 경계를 포함하고 미래 신고와 중복 reporter를 제외한다", () => {
  const now = new Date("2026-08-21T12:00:00.000Z");
  const cutoff = now.getTime() - MESSAGE_GLOBAL_VISIBILITY_WINDOW_MILLIS;
  const result = messageGlobalVisibilityEvaluation([
    {reporterModerationPrincipalID: "a", priority: "urgent", receivedAt: new Date(cutoff)},
    {reporterModerationPrincipalID: "a", priority: "general", receivedAt: new Date(now)},
    {reporterModerationPrincipalID: "b", priority: "urgent", receivedAt: new Date(now)},
    {reporterModerationPrincipalID: "expired", priority: "urgent", receivedAt: new Date(cutoff - 1)},
    {reporterModerationPrincipalID: "future", priority: "urgent", receivedAt: new Date(now.getTime() + 1)},
  ], now);
  assert.deepEqual(result, {
    urgentDistinctReporterCount: 2,
    totalDistinctReporterCount: 2,
    shouldHide: true,
  });
});

test("전체 사유 고유 reporter 3명도 전역 비노출을 만든다", () => {
  const now = new Date("2026-08-21T12:00:00.000Z");
  const result = messageGlobalVisibilityEvaluation([
    {reporterModerationPrincipalID: "a", priority: "general", receivedAt: now},
    {reporterModerationPrincipalID: "b", priority: "general", receivedAt: now},
    {reporterModerationPrincipalID: "c", priority: "general", receivedAt: now},
  ], now);
  assert.equal(result.shouldHide, true);
  assert.equal(result.urgentDistinctReporterCount, 0);
});

test("작성자 패턴은 서로 다른 메시지 3개와 reporter 2명을 모두 요구한다", () => {
  const now = new Date("2026-08-21T12:00:00.000Z");
  const recent = new Date(now.getTime() - 60_000);
  const oneReporter = messageAuthorPatternEvaluation({
    reportedMessages: ["m1", "m2", "m3"].map((id) => ({id, lastReportedAt: recent})),
    reporters: [{id: "r1", lastReportedAt: recent}],
    now,
  });
  assert.equal(oneReporter.isActive, false);

  const qualified = messageAuthorPatternEvaluation({
    reportedMessages: ["m1", "m2", "m3"].map((id) => ({id, lastReportedAt: recent})),
    reporters: ["r1", "r2"].map((id) => ({id, lastReportedAt: recent})),
    now,
  });
  assert.equal(qualified.isActive, true);
  assert.equal(qualified.distinctMessageCount, 3);
  assert.equal(qualified.distinctReporterCount, 2);
});

test("작성자 패턴의 7일 시작 경계는 계산에 포함되지만 reviewUntil과 같으면 비활성이다", () => {
  const now = new Date("2026-08-21T12:00:00.000Z");
  const cutoff = new Date(now.getTime() - MESSAGE_AUTHOR_PATTERN_WINDOW_MILLIS);
  const evaluation = messageAuthorPatternEvaluation({
    reportedMessages: ["m1", "m2", "m3"].map((id) => ({id, lastReportedAt: cutoff})),
    reporters: ["r1", "r2"].map((id) => ({id, lastReportedAt: cutoff})),
    now,
  });
  assert.equal(evaluation.messagePatternReviewUntil?.getTime(), now.getTime());
  assert.equal(evaluation.isActive, false);
});

test("검토 중과 appeal 또는 legal hold는 evidence cleanup을 보류한다", () => {
  const base = {
    decision: null,
    decisionAt: null,
    appealState: "none" as const,
    appealResolvedAt: null,
    legalHoldActive: false,
  };
  assert.deepEqual(messageEvidenceRetention({
    ...base,
    reviewState: "inReview",
  }), {retentionClass: "reviewOpen", deleteAfter: null});

  const decisionAt = new Date("2026-08-21T12:00:00.000Z");
  assert.deepEqual(messageEvidenceRetention({
    reviewState: "resolved",
    decision: "temporaryRestriction",
    decisionAt,
    appealState: "open",
    appealResolvedAt: null,
    legalHoldActive: false,
  }), {retentionClass: "appealOpen", deleteAfter: null});
  assert.deepEqual(messageEvidenceRetention({
    reviewState: "resolved",
    decision: "warningOnly",
    decisionAt,
    appealState: "none",
    appealResolvedAt: null,
    legalHoldActive: true,
  }), {retentionClass: "legalHold", deleteAfter: null});
});

test("기각·삭제만·경고만은 즉시, 계정 제재는 30일 뒤 cleanup한다", () => {
  const decisionAt = new Date("2026-08-21T12:00:00.000Z");
  const immediate = messageEvidenceRetention({
    reviewState: "dismissed",
    decision: "dismissed",
    decisionAt,
    appealState: "none",
    appealResolvedAt: null,
    legalHoldActive: false,
  });
  assert.equal(immediate.deleteAfter?.getTime(), decisionAt.getTime());
  assert.equal(isMessageEvidenceCleanupDue(immediate, decisionAt), true);

  const sanction = messageEvidenceRetention({
    reviewState: "resolved",
    decision: "permanentSuspension",
    decisionAt,
    appealState: "none",
    appealResolvedAt: null,
    legalHoldActive: false,
  });
  assert.equal(
    sanction.deleteAfter?.getTime(),
    decisionAt.getTime() + MESSAGE_SANCTION_APPEAL_RETENTION_MILLIS,
  );
});

test("이의제기 해결 시 해결 시각부터 즉시 cleanup할 수 있다", () => {
  const resolvedAt = new Date("2026-08-25T12:00:00.000Z");
  const retention = messageEvidenceRetention({
    reviewState: "resolved",
    decision: "temporaryRestriction",
    decisionAt: new Date("2026-08-21T12:00:00.000Z"),
    appealState: "resolved",
    appealResolvedAt: resolvedAt,
    legalHoldActive: false,
  });
  assert.equal(retention.retentionClass, "deleteAfterDecision");
  assert.equal(retention.deleteAfter?.getTime(), resolvedAt.getTime());
});

test("evidence와 job 상태는 허용된 방향으로만 전이한다", () => {
  assert.equal(canTransitionMessageEvidence("copyPending", "copying"), true);
  assert.equal(canTransitionMessageEvidence("copying", "available"), true);
  assert.equal(canTransitionMessageEvidence("available", "failed"), false);
  assert.equal(canTransitionMessageEvidence("deleted", "available"), false);
  assert.equal(canTransitionMessageEvidenceJob("processing", "retryPending"), true);
  assert.equal(canTransitionMessageEvidenceJob("retryPending", "processing"), true);
  assert.equal(canTransitionMessageEvidenceJob("succeeded", "processing"), false);
  assert.equal(
    canTransitionMessageEvidenceCleanupJob("awaitingEvidence", "pending"),
    true,
  );
  assert.equal(
    canTransitionMessageEvidenceCleanupJob("awaitingEvidence", "succeeded"),
    false,
  );
});
