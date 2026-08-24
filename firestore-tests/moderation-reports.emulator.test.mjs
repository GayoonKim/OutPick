import assert from "node:assert/strict";
import {after, beforeEach, describe, test} from "node:test";
import {Timestamp} from "../functions/node_modules/firebase-admin/lib/firestore/index.js";
import {db} from "../functions/lib/core/firebase.js";
import {
  submitUserReportService,
} from "../functions/lib/moderation/reports/service.js";
import {
  acceptMessageEvidenceBundleService,
  submitMessageReportService,
} from "../functions/lib/moderation/messageEvidence/service.js";
import {
  deleteChatMessageService,
  messageCleanupJobID,
} from "../functions/lib/chat/moderation/service.js";
import {
  messageIncidentID,
} from "../functions/lib/moderation/messageEvidence/contracts.js";
import {
  mutateAccountModerationService,
  mutateModerationReviewService,
} from "../functions/lib/moderation/admin/service.js";

const reporterUID = "moderation-reporter";
const targetUID = "moderation-target";
const reporterPrincipalID = "principal-reporter";
const targetPrincipalID = "principal-target";
const now = new Date("2026-08-10T07:00:30.000Z");

function requestID(sequence) {
  return `123e4567-e89b-42d3-a456-${String(sequence).padStart(12, "0")}`;
}

async function clearFixtures() {
  await Promise.all([
    db.recursiveDelete(db.collection("moderationAccounts").doc(reporterUID)),
    db.recursiveDelete(db.collection("moderationAccounts").doc(targetUID)),
    db.recursiveDelete(db.collection("moderationUserReports")),
    db.recursiveDelete(db.collection("moderationReportRateLimitBuckets")),
    db.recursiveDelete(db.collection("moderationAuditLogs")),
    db.recursiveDelete(db.collection("moderationMessageReportRequests")),
    db.recursiveDelete(db.collection("moderationMessageReportPreparations")),
    db.recursiveDelete(db.collection("moderationMessageIncidents")),
    db.recursiveDelete(db.collection("moderationMessageEvidence")),
    db.recursiveDelete(db.collection("moderationMessageGuards")),
    db.recursiveDelete(db.collection("moderationEvidenceCopyJobs")),
    db.recursiveDelete(db.collection("chatMessageCleanupJobs")),
    db.recursiveDelete(db.collection("moderationPrincipals").doc(targetPrincipalID)),
    db.recursiveDelete(db.collection("platformAdmins").doc(targetUID)),
    db.recursiveDelete(db.collection("Rooms").doc("moderation-room")),
    db.recursiveDelete(db.collection("users").doc(reporterUID)),
    db.recursiveDelete(db.collection("users").doc(targetUID)),
  ]);
}

async function seedAccounts() {
  await Promise.all([
    db.collection("users").doc(reporterUID).set({accountStatus: "active"}),
    db.collection("users").doc(targetUID).set({accountStatus: "active"}),
    db.collection("moderationAccounts").doc(reporterUID).set({
      accountStatus: "active",
      moderationPrincipalID: reporterPrincipalID,
      moderationStatus: "active",
      stateVersion: 1,
    }),
    db.collection("moderationAccounts").doc(targetUID).set({
      accountStatus: "active",
      moderationPrincipalID: targetPrincipalID,
      moderationStatus: "active",
      stateVersion: 1,
    }),
  ]);
}

function userReport(sequence, reason = "spam") {
  return {
    targetUID,
    reason,
    detail: null,
    roomID: null,
    triggerMessageID: null,
    clientRequestID: requestID(sequence),
  };
}

beforeEach(async () => {
  await clearFixtures();
  await seedAccounts();
});
after(clearFixtures);

describe("moderation report transactions", () => {
  test("동시 동일 요청은 한 submission과 한 rate count로 수렴한다", async () => {
    const receipts = await Promise.all([
      submitUserReportService(reporterUID, userReport(1), now),
      submitUserReportService(reporterUID, userReport(1), now),
      submitUserReportService(reporterUID, userReport(1), now),
    ]);

    assert.equal(new Set(receipts.map((receipt) => receipt.submissionID)).size, 1);
    assert.equal(receipts.filter((receipt) => !receipt.deduplicated).length, 1);
    const aggregate = await db.collection("moderationUserReports")
      .doc(targetPrincipalID).get();
    const submissions = await aggregate.ref.collection("submissions").get();
    const rateBuckets = await db.collection("moderationReportRateLimitBuckets").get();
    assert.equal(aggregate.data()?.totalSubmissionCount, 1);
    assert.equal(aggregate.data()?.uniqueReporterCount, 1);
    assert.equal(submissions.size, 1);
    assert.equal(rateBuckets.docs[0]?.data().acceptedCount, 1);
  });

  test("서로 다른 10건은 허용하고 11번째만 다음 분까지 거부한다", async () => {
    for (let sequence = 1; sequence <= 10; sequence += 1) {
      await submitUserReportService(reporterUID, userReport(sequence), now);
    }
    await assert.rejects(
      submitUserReportService(reporterUID, userReport(11), now),
      (error) => error?.code === "resource-exhausted" &&
        error?.details?.retryAt === "2026-08-10T07:01:00.000Z",
    );
    const aggregate = await db.collection("moderationUserReports")
      .doc(targetPrincipalID).get();
    assert.equal(aggregate.data()?.totalSubmissionCount, 10);
    assert.equal(aggregate.data()?.uniqueReporterCount, 1);
  });

  test("terminal case의 새 사건은 reopen하고 version을 올린다", async () => {
    await submitUserReportService(reporterUID, userReport(1), now);
    const aggregateRef = db.collection("moderationUserReports").doc(targetPrincipalID);
    await aggregateRef.update({
      reviewState: "resolved",
      reviewRevision: 2,
      caseVersion: 7,
    });
    await submitUserReportService(reporterUID, userReport(2), now);
    const aggregate = await aggregateRef.get();
    assert.equal(aggregate.data()?.reviewState, "open");
    assert.equal(aggregate.data()?.reviewRevision, 3);
    assert.equal(aggregate.data()?.caseVersion, 8);
  });

  test("자기 신고, 없는 target, membership 없는 room context를 거부한다", async () => {
    await assert.rejects(
      submitUserReportService(reporterUID, {
        ...userReport(20),
        targetUID: reporterUID,
      }, now),
      (error) => error?.code === "failed-precondition",
    );
    await assert.rejects(
      submitUserReportService(reporterUID, {
        ...userReport(21),
        targetUID: "missing-target",
      }, now),
      (error) => error?.code === "not-found",
    );
    await db.collection("Rooms").doc("moderation-room").set({
      lifecycleStatus: "active",
    });
    await assert.rejects(
      submitUserReportService(reporterUID, {
        ...userReport(22),
        roomID: "moderation-room",
      }, now),
      (error) => error?.code === "permission-denied",
    );
  });

  test("동시 관리자 review mutation 중 하나만 현재 version을 소비한다", async () => {
    const aggregateRef = db.collection("moderationUserReports").doc(targetPrincipalID);
    await aggregateRef.set({
      schemaVersion: 1,
      reviewState: "open",
      reviewRevision: 0,
      caseVersion: 1,
      uniqueReporterCount: 1,
      totalSubmissionCount: 1,
      reasonCounts: {spam: 1},
      priorityClass: "general",
      slaDueAt: Timestamp.fromDate(new Date("2026-08-13T07:00:00.000Z")),
      firstReportedAt: Timestamp.fromDate(now),
      lastReportedAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
    const common = {
      targetType: "user",
      targetID: targetPrincipalID,
      expectedCaseVersion: 1,
      reasonCode: "reviewed",
    };
    const results = await Promise.allSettled([
      mutateModerationReviewService("admin-a", {
        ...common,
        action: "resolveReview",
        clientRequestID: requestID(101),
      }, now),
      mutateModerationReviewService("admin-b", {
        ...common,
        action: "dismissReview",
        clientRequestID: requestID(102),
      }, now),
    ]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(results.filter((result) =>
      result.status === "rejected" && result.reason?.code === "aborted").length, 1);
    const aggregate = await aggregateRef.get();
    const audits = await db.collection("moderationAuditLogs").get();
    assert.equal(aggregate.data()?.caseVersion, 2);
    assert.equal(audits.size, 1);
  });

  test("메시지 신고의 과거 request receipt는 terminal review 뒤에도 새 revision이 되지 않는다", async () => {
    const roomRef = db.collection("Rooms").doc("moderation-room");
    await Promise.all([
      roomRef.set({lifecycleStatus: "active"}),
      roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("Messages").doc("message-1").set({
        ID: "message-1",
        roomID: "moderation-room",
        senderUID: targetUID,
        messageType: "Text",
        message: "신고 증거",
        msg: "신고 증거",
        attachments: [],
        isDeleted: false,
        moderationVisibilityState: "visible",
        seq: 1,
      }),
    ]);
    const input = {
      roomID: "moderation-room",
      messageID: "message-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(301),
    };
    const first = await submitMessageReportService(reporterUID, input, now);
    assert.equal(first.status, "accepted");
    const incidentRef = db.collection("moderationMessageIncidents")
      .doc(messageIncidentID(input.roomID, input.messageID));
    await incidentRef.update({reviewState: "dismissed", acceptanceState: "reviewable"});

    const replay = await submitMessageReportService(reporterUID, input, new Date(now.getTime() + 60_000));
    assert.equal(replay.status, "accepted");
    assert.equal(replay.deduplicated, true);
    assert.equal((await incidentRef.get()).data()?.reviewRevision, 0);

    const reopened = await submitMessageReportService(reporterUID, {
      ...input,
      reason: "spam",
      clientRequestID: requestID(302),
    }, new Date(now.getTime() + 120_000));
    assert.equal(reopened.status, "accepted");
    const reopenedIncident = (await incidentRef.get()).data();
    assert.equal(reopenedIncident?.reviewRevision, 1);
    assert.equal(reopenedIncident?.queueClass, "holding");
    assert.deepEqual(reopenedIncident?.reasonCounts, {spam: 1});
    assert.equal(reopenedIncident?.totalDistinctReporterCount24h, 1);
  });

  test("메시지 신고의 새 UUID receipt는 1분 10회로 제한하고 같은 UUID replay는 무료다", async () => {
    const roomRef = db.collection("Rooms").doc("moderation-room");
    await Promise.all([
      roomRef.set({lifecycleStatus: "active"}),
      roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("Messages").doc("message-1").set({
        ID: "message-1",
        roomID: "moderation-room",
        senderUID: targetUID,
        messageType: "Text",
        message: "신고 증거",
        msg: "신고 증거",
        attachments: [],
        isDeleted: false,
        moderationVisibilityState: "visible",
        seq: 1,
      }),
    ]);
    const input = {
      roomID: "moderation-room",
      messageID: "message-1",
      reason: "spam",
      detail: null,
      clientRequestID: requestID(401),
    };
    const first = await submitMessageReportService(reporterUID, input, now);
    assert.equal(first.status, "accepted");
    for (let sequence = 402; sequence <= 410; sequence += 1) {
      const duplicate = await submitMessageReportService(reporterUID, {
        ...input,
        clientRequestID: requestID(sequence),
      }, now);
      assert.equal(duplicate.status, "alreadyReported");
    }
    await assert.rejects(
      submitMessageReportService(reporterUID, {
        ...input,
        clientRequestID: requestID(411),
      }, now),
      (error) => error?.code === "resource-exhausted",
    );
    const replay = await submitMessageReportService(reporterUID, input, now);
    assert.equal(replay.status, "accepted");
    assert.equal(replay.deduplicated, true);
    const buckets = await db.collection("moderationReportRateLimitBuckets").get();
    assert.equal(buckets.docs[0]?.data().messageRequestCount, 10);
    assert.equal(buckets.docs[0]?.data().messagePreparationCount, 1);
    assert.equal(buckets.docs[0]?.data().technicalOperationCount, 10);
    assert.equal((await db.collection("moderationMessageReportRequests").get()).size, 10);
  });

  test("미디어 evidence available drain은 processing receipt를 accepted로 확정한다", async () => {
    const roomRef = db.collection("Rooms").doc("moderation-room");
    await Promise.all([
      roomRef.set({lifecycleStatus: "active"}),
      roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("Messages").doc("media-1").set({
        ID: "media-1",
        roomID: "moderation-room",
        senderUID: targetUID,
        messageType: "Image",
        message: "",
        msg: "",
        attachments: [{
          attachmentID: "attachment-1",
          bucketOriginal: "ready-bucket",
          pathOriginal: "rooms/moderation-room/messages/media-1/attachments/attachment-1/display",
          generationOriginal: "1",
          bytesOriginal: 1024,
          contentTypeOriginal: "image/jpeg",
        }],
        isDeleted: false,
        moderationVisibilityState: "visible",
        seq: 2,
      }),
    ]);
    const input = {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(501),
    };
    const processing = await submitMessageReportService(reporterUID, input, now);
    assert.equal(processing.status, "processing");
    const aliasInput = {...input, clientRequestID: requestID(502)};
    const aliasProcessing = await submitMessageReportService(
      reporterUID,
      aliasInput,
      new Date(now.getTime() + 60_000),
    );
    assert.equal(aliasProcessing.status, "processing");
    const preparation = (await db.collection("moderationMessageReportPreparations").get()).docs[0];
    const bundleID = preparation.data().bundleID;
    await db.collection("moderationMessageEvidence").doc(bundleID).update({state: "available"});
    const accepted = await acceptMessageEvidenceBundleService(bundleID, 0, now, db);
    assert.deepEqual(accepted, {
      acceptedPreparationCount: 1,
      remainingPreparationCount: 0,
      acceptanceState: "reviewable",
    });
    const receiptsAfterDrain = await db.collection("moderationMessageReportRequests").get();
    assert.equal(receiptsAfterDrain.docs.filter((document) => document.data().status === "accepted").length, 1);
    assert.equal(receiptsAfterDrain.docs.filter((document) => document.data().status === "processing").length, 1);
    const aliasReplay = await submitMessageReportService(reporterUID, aliasInput, now);
    assert.equal(aliasReplay.status, "accepted");
    assert.equal(aliasReplay.deduplicated, true);
    const replay = await submitMessageReportService(reporterUID, input, now);
    assert.equal(replay.status, "accepted");
    assert.equal(replay.deduplicated, true);
  });

  test("미디어 evidence 실패 재시작은 cleanup과 동일 generation terminal 상태를 요구한다", async () => {
    const roomRef = db.collection("Rooms").doc("moderation-room");
    await Promise.all([
      roomRef.set({lifecycleStatus: "active"}),
      roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("Messages").doc("media-1").set({
        ID: "media-1",
        roomID: "moderation-room",
        senderUID: targetUID,
        messageType: "Image",
        message: "",
        msg: "",
        attachments: [{
          attachmentID: "attachment-1",
          bucketOriginal: "ready-bucket",
          pathOriginal: "rooms/moderation-room/messages/media-1/attachments/attachment-1/display",
          generationOriginal: "1",
          bytesOriginal: 1024,
          contentTypeOriginal: "image/jpeg",
        }],
        isDeleted: false,
        moderationVisibilityState: "visible",
        seq: 2,
      }),
    ]);
    const initialInput = {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(511),
    };
    const initial = await submitMessageReportService(reporterUID, initialInput, now);
    assert.equal(initial.status, "processing");
    const preparation = (await db.collection("moderationMessageReportPreparations").get()).docs[0];
    const bundleRef = db.collection("moderationMessageEvidence").doc(preparation.data().bundleID);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const initialRequest = (await db.collection("moderationMessageReportRequests").get()).docs[0];
    await Promise.all([
      preparation.ref.update({status: "failed", failedAt: Timestamp.fromDate(now), lastErrorCode: "EVIDENCE_COPY_FAILED"}),
      bundleRef.update({state: "failed", objectPaths: ["partial/object"]}),
      copyJob.ref.update({status: "failed", lastErrorCode: "EVIDENCE_COPY_FAILED"}),
      initialRequest.ref.update({status: "failed", lastErrorCode: "EVIDENCE_COPY_FAILED"}),
    ]);
    const retryInput = {...initialInput, clientRequestID: requestID(512)};
    await assert.rejects(
      submitMessageReportService(reporterUID, retryInput, new Date(now.getTime() + 60_000)),
      (error) => error?.code === "failed-precondition",
    );
    assert.equal((await db.collection("moderationMessageReportRequests").get()).size, 1);

    await bundleRef.update({objectPaths: []});
    const restarted = await submitMessageReportService(
      reporterUID,
      retryInput,
      new Date(now.getTime() + 60_000),
    );
    assert.equal(restarted.status, "processing");
    assert.equal((await preparation.ref.get()).data()?.attemptGeneration, 1);
    assert.equal((await bundleRef.get()).data()?.attemptGeneration, 1);
    assert.equal((await copyJob.ref.get()).data()?.attemptGeneration, 1);
    assert.equal((await copyJob.ref.get()).data()?.status, "pending");
    const oldReplay = await submitMessageReportService(reporterUID, initialInput, now);
    assert.equal(oldReplay.status, "failed");

    await bundleRef.update({state: "available"});
    await assert.rejects(
      acceptMessageEvidenceBundleService(preparation.data().bundleID, 0, now, db),
      (error) => error?.code === "failed-precondition",
    );
    const accepted = await acceptMessageEvidenceBundleService(preparation.data().bundleID, 1, now, db);
    assert.equal(accepted.acceptedPreparationCount, 1);
  });

  test("미디어 신고가 삭제보다 먼저면 public cleanup은 evidence를 기다린다", async () => {
    const roomRef = db.collection("Rooms").doc("moderation-room");
    await Promise.all([
      roomRef.set({lifecycleStatus: "active", creatorUID: targetUID}),
      roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("members").doc(targetUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("Messages").doc("media-1").set({
        ID: "media-1",
        roomID: "moderation-room",
        senderUID: targetUID,
        messageType: "Image",
        message: "",
        msg: "",
        attachments: [{
          attachmentID: "attachment-1",
          bucketOriginal: "ready-bucket",
          pathOriginal: "rooms/moderation-room/messages/media-1/attachments/attachment-1/display",
          generationOriginal: "1",
          bytesOriginal: 1024,
          contentTypeOriginal: "image/jpeg",
        }],
        isDeleted: false,
        moderationVisibilityState: "visible",
        seq: 2,
      }),
    ]);
    const processing = await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(601),
    }, now);
    assert.equal(processing.status, "processing");
    const deleted = await deleteChatMessageService(targetUID, null, {
      roomID: "moderation-room",
      messageID: "media-1",
      expectedSeq: 2,
      reasonCode: null,
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: requestID(602),
    }, now, db);
    assert.equal(deleted.cleanupStatus, "awaitingEvidence");
    const cleanup = await db.collection("chatMessageCleanupJobs")
      .doc(messageCleanupJobID("moderation-room", "media-1")).get();
    assert.equal(cleanup.data()?.status, "awaitingEvidence");
  });

  test("삭제 tombstone이 먼저면 transport receipt만 만들고 evidence는 만들지 않는다", async () => {
    const roomRef = db.collection("Rooms").doc("moderation-room");
    await Promise.all([
      roomRef.set({lifecycleStatus: "active"}),
      roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
      roomRef.collection("Messages").doc("deleted-1").set({
        ID: "deleted-1",
        roomID: "moderation-room",
        isDeleted: true,
        moderationVisibilityState: "deleted",
        deletionPresentation: "moderationRemoved",
        seq: 3,
      }),
    ]);
    const receipt = await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "deleted-1",
      reason: "spam",
      detail: null,
      clientRequestID: requestID(701),
    }, now);
    assert.equal(receipt.status, "messageAlreadyDeleted");
    assert.equal((await db.collection("moderationMessageReportRequests").get()).size, 1);
    assert.equal((await db.collection("moderationMessageReportPreparations").get()).size, 0);
    assert.equal((await db.collection("moderationMessageEvidence").get()).size, 0);
    const buckets = await db.collection("moderationReportRateLimitBuckets").get();
    assert.equal(buckets.docs[0]?.data().messageRequestCount, 1);
    assert.equal(buckets.docs[0]?.data().messagePreparationCount, 0);
  });

  test("관리자 자신과 active platform admin 제재를 거부한다", async () => {
    await db.collection("moderationPrincipals").doc(targetPrincipalID).set({
      moderationStatus: "active",
      restrictedUntil: null,
      stateVersion: 1,
    });
    const input = {
      targetUID,
      action: "permanentlySuspendAccount",
      restrictedUntil: null,
      reasonCode: "confirmed-abuse",
      reportTargetType: null,
      reportTargetID: null,
      expectedStateVersion: 1,
      clientRequestID: requestID(201),
    };
    await assert.rejects(
      mutateAccountModerationService(targetUID, input, now),
      (error) => error?.details?.errorCode === "SELF_ADMIN_ACTION",
    );
    await db.collection("platformAdmins").doc(targetUID).set({
      isActive: true,
      revokedAt: null,
    });
    await assert.rejects(
      mutateAccountModerationService("admin-a", {
        ...input,
        clientRequestID: requestID(202),
      }, now),
      (error) => error?.details?.errorCode === "PROTECTED_ADMIN_TARGET",
    );
  });
});
