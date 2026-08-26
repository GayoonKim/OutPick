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
  processMessageEvidenceCopyJob,
} from "../functions/lib/moderation/messageEvidence/evidenceCopy.js";
import {
  enqueueDueMessageEvidenceRetention,
  processMessageEvidenceCleanupJob,
} from "../functions/lib/moderation/messageEvidence/evidenceCleanup.js";
import {
  getModerationReportDetailService,
  listModerationReportsService,
  mutateAccountModerationService,
  mutateModerationReviewService,
} from "../functions/lib/moderation/admin/service.js";
import {resolveMessageModerationService} from "../functions/lib/moderation/admin/messageResolution.js";
import {issueMessageEvidenceViewURLService} from "../functions/lib/moderation/admin/evidenceAccess.js";

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
    db.recursiveDelete(db.collection("moderationEvidenceCleanupJobs")),
    db.recursiveDelete(db.collection("moderationConfirmedViolations")),
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

async function seedMediaMessage(messageID = "media-1") {
  const roomRef = db.collection("Rooms").doc("moderation-room");
  await Promise.all([
    roomRef.set({lifecycleStatus: "active", creatorUID: targetUID}),
    roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
    roomRef.collection("members").doc(targetUID).set({joinedAt: Timestamp.fromDate(now)}),
    roomRef.collection("Messages").doc(messageID).set({
      ID: messageID,
      roomID: "moderation-room",
      senderUID: targetUID,
      messageType: "Image",
      message: "",
      msg: "",
      attachments: [{
        attachmentID: "attachment-1",
        bucketOriginal: "ready-bucket",
        pathOriginal: `rooms/moderation-room/messages/${messageID}/attachments/attachment-1/display`,
        generationOriginal: "1",
        bytesOriginal: 1024,
        contentTypeOriginal: "image/jpeg",
      }],
      isDeleted: false,
      moderationVisibilityState: "visible",
      seq: 2,
    }),
  ]);
}

async function seedTextMessage(messageID = "text-1") {
  const roomRef = db.collection("Rooms").doc("moderation-room");
  await Promise.all([
    roomRef.set({lifecycleStatus: "active", creatorUID: targetUID, lastMessageSeq: 1, lastMessage: "신고 대상"}),
    roomRef.collection("members").doc(reporterUID).set({joinedAt: Timestamp.fromDate(now)}),
    roomRef.collection("members").doc(targetUID).set({joinedAt: Timestamp.fromDate(now)}),
    roomRef.collection("Messages").doc(messageID).set({
      ID: messageID, roomID: "moderation-room", senderUID: targetUID,
      messageType: "Text", message: "신고 대상", msg: "신고 대상",
      isDeleted: false, moderationVisibilityState: "visible", seq: 1,
    }),
  ]);
}

function fakeEvidenceStorage({copyFailures = 0, failOnCopyCalls = []} = {}) {
  const objects = new Map();
  const calls = {copy: 0, deleteAttempt: 0, deleteEvidence: 0};
  return {
    objects,
    calls,
    storage: {
      copy: async (input) => {
        calls.copy += 1;
        const existing = objects.get(input.destinationPath);
        if (existing) return existing;
        if (calls.copy <= copyFailures || failOnCopyCalls.includes(calls.copy)) {
          throw new Error("storage unavailable");
        }
        const object = {
          attachmentID: input.source.attachmentID,
          bucket: input.destinationBucket,
          path: input.destinationPath,
          destinationGeneration: String(1000 + calls.copy),
          sourceGeneration: input.source.generation,
          bytes: input.source.bytes,
          contentType: input.source.contentType,
          crc32c: "crc32c",
          attemptGeneration: input.attemptGeneration,
          bundleID: input.bundleID,
        };
        objects.set(input.destinationPath, object);
        return object;
      },
      deleteAttemptObject: async (input) => {
        calls.deleteAttempt += 1;
        const object = objects.get(input.destinationPath);
        if (!object) return;
        if (object.bundleID !== input.bundleID || object.attemptGeneration !== input.attemptGeneration) {
          throw new Error("ownership mismatch");
        }
        objects.delete(input.destinationPath);
      },
      deleteEvidenceObject: async (input) => {
        calls.deleteEvidence += 1;
        const object = objects.get(input.object.path);
        if (!object) return;
        if (object.destinationGeneration !== input.object.destinationGeneration || object.bundleID !== input.bundleID) {
          throw new Error("generation mismatch");
        }
        objects.delete(input.object.path);
      },
    },
  };
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

  test("evidence copy worker는 generation 경로 복사·accepted drain·public cleanup 해제를 한 번만 확정한다", async () => {
    await seedMediaMessage();
    const input = {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(503),
    };
    assert.equal((await submitMessageReportService(reporterUID, input, now)).status, "processing");
    const deleted = await deleteChatMessageService(targetUID, null, {
      roomID: "moderation-room",
      messageID: "media-1",
      expectedSeq: 2,
      reasonCode: null,
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: requestID(504),
    }, now, db);
    assert.equal(deleted.cleanupStatus, "awaitingEvidence");
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage();
    assert.equal(await processMessageEvidenceCopyJob({
      jobID: copyJob.id,
      firestore: db,
      storage: fake.storage,
      readyBucket: "ready-bucket",
      evidenceBucket: "evidence-bucket",
      now,
    }), true);
    assert.equal(fake.calls.copy, 1);
    const completedJob = await copyJob.ref.get();
    assert.equal(completedJob.data()?.status, "succeeded");
    assert.equal(completedJob.data()?.phase, "completed");
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    assert.equal(bundle.data().state, "available");
    assert.equal(bundle.data().sourceObjects, undefined);
    assert.match(bundle.data().evidenceObjects[0].path, /\/g0\/attachment-1\/display$/);
    const preparation = (await db.collection("moderationMessageReportPreparations").get()).docs[0];
    assert.equal(preparation.data().status, "accepted");
    const cleanup = await db.collection("chatMessageCleanupJobs")
      .doc(messageCleanupJobID("moderation-room", "media-1")).get();
    assert.equal(cleanup.data()?.status, "pending");
    assert.equal(await processMessageEvidenceCopyJob({
      jobID: copyJob.id,
      firestore: db,
      storage: fake.storage,
      readyBucket: "ready-bucket",
      evidenceBucket: "evidence-bucket",
      now,
    }), false);
    assert.equal(fake.calls.copy, 1);
  });

  test("evidence acceptance drain은 실행당 30건만 확정하고 다음 lease에서 이어간다", async () => {
    await seedMediaMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(510),
    }, now);
    const originalPreparation = (await db.collection("moderationMessageReportPreparations").get()).docs[0];
    const originalData = originalPreparation.data();
    const extraWrites = [];
    for (let index = 1; index <= 30; index += 1) {
      const preparationRef = db.collection("moderationMessageReportPreparations").doc(`extra-preparation-${index}`);
      const receiptRef = db.collection("moderationMessageReportRequests").doc(`extra-receipt-${index}`);
      extraWrites.push(preparationRef.set({
        ...originalData,
        reporterID: `extra-reporter-${index}`,
        reporterModerationPrincipalID: `extra-principal-${index}`,
        initialRequestID: receiptRef.id,
        requestedAt: Timestamp.fromMillis(now.getTime() + index),
        createdAt: Timestamp.fromMillis(now.getTime() + index),
        updatedAt: Timestamp.fromMillis(now.getTime() + index),
      }));
      extraWrites.push(receiptRef.set({
        schemaVersion: 1,
        preparationID: preparationRef.id,
        attemptGeneration: 0,
        clientRequestID: requestID(510 + index),
        status: "processing",
        createdAt: Timestamp.fromMillis(now.getTime() + index),
        updatedAt: Timestamp.fromMillis(now.getTime() + index),
      }));
    }
    await Promise.all(extraWrites);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage();
    assert.equal(await processMessageEvidenceCopyJob({
      jobID: copyJob.id,
      firestore: db,
      storage: fake.storage,
      readyBucket: "ready-bucket",
      evidenceBucket: "evidence-bucket",
      now,
    }), false);
    const afterFirstDrain = await db.collection("moderationMessageReportPreparations").get();
    assert.equal(afterFirstDrain.docs.filter((document) => document.data().status === "accepted").length, 30);
    assert.equal(afterFirstDrain.docs.filter((document) => document.data().status === "processing").length, 1);
    assert.equal((await copyJob.ref.get()).data()?.phase, "acceptanceDrain");
    assert.equal((await copyJob.ref.get()).data()?.status, "retryPending");
    assert.equal(fake.calls.copy, 1);
    assert.equal(await processMessageEvidenceCopyJob({
      jobID: copyJob.id,
      firestore: db,
      storage: fake.storage,
      readyBucket: "ready-bucket",
      evidenceBucket: "evidence-bucket",
      now: new Date(now.getTime() + 60_000),
    }), true);
    const afterSecondDrain = await db.collection("moderationMessageReportPreparations").get();
    assert.equal(afterSecondDrain.docs.filter((document) => document.data().status === "accepted").length, 31);
    assert.equal((await copyJob.ref.get()).data()?.status, "succeeded");
    assert.equal(fake.calls.copy, 1);
  });

  test("evidence copy는 최초 포함 3회 실패 뒤 partial cleanup·failed receipt·public cleanup 해제로 수렴한다", async () => {
    await seedMediaMessage();
    const input = {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(505),
    };
    assert.equal((await submitMessageReportService(reporterUID, input, now)).status, "processing");
    await deleteChatMessageService(targetUID, null, {
      roomID: "moderation-room",
      messageID: "media-1",
      expectedSeq: 2,
      reasonCode: null,
      reportTargetType: null,
      reportTargetID: null,
      clientRequestID: requestID(506),
    }, now, db);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage({copyFailures: 3});
    for (const offset of [0, 60_000, 180_000]) {
      assert.equal(await processMessageEvidenceCopyJob({
        jobID: copyJob.id,
        firestore: db,
        storage: fake.storage,
        readyBucket: "ready-bucket",
        evidenceBucket: "evidence-bucket",
        now: new Date(now.getTime() + offset),
      }), false);
    }
    assert.equal(fake.calls.copy, 3);
    assert.equal(fake.calls.deleteAttempt, 1);
    assert.equal((await copyJob.ref.get()).data()?.status, "failed");
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    assert.equal(bundle.data().state, "failed");
    assert.equal(bundle.data().textSnapshot, undefined);
    assert.deepEqual(bundle.data().objectPaths, []);
    const preparation = (await db.collection("moderationMessageReportPreparations").get()).docs[0];
    const receipt = (await db.collection("moderationMessageReportRequests").get()).docs[0];
    assert.equal(preparation.data().status, "failed");
    assert.equal(receipt.data().status, "failed");
    const cleanup = await db.collection("chatMessageCleanupJobs")
      .doc(messageCleanupJobID("moderation-room", "media-1")).get();
    assert.equal(cleanup.data()?.status, "pending");
  });

  test("일부 attachment만 복사된 3회 실패는 generation prefix의 기존 객체까지 제거한다", async () => {
    await seedMediaMessage();
    const messageRef = db.collection("Rooms").doc("moderation-room").collection("Messages").doc("media-1");
    const message = (await messageRef.get()).data();
    await messageRef.update({
      attachments: [...message.attachments, {
        attachmentID: "attachment-2",
        bucketOriginal: "ready-bucket",
        pathOriginal: "rooms/moderation-room/messages/media-1/attachments/attachment-2/display",
        generationOriginal: "2",
        bytesOriginal: 2048,
        contentTypeOriginal: "image/png",
      }],
    });
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(509),
    }, now);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage({failOnCopyCalls: [2, 4, 6]});
    for (const offset of [0, 60_000, 180_000]) {
      await processMessageEvidenceCopyJob({jobID: copyJob.id, firestore: db, storage: fake.storage, readyBucket: "ready-bucket", evidenceBucket: "evidence-bucket", now: new Date(now.getTime() + offset)});
    }
    assert.equal(fake.calls.copy, 6);
    assert.equal(fake.calls.deleteAttempt, 2);
    assert.equal(fake.objects.size, 0);
    assert.equal((await copyJob.ref.get()).data()?.status, "failed");
  });

  test("3회차 copy lease 중단은 만료 뒤 새 시도 없이 partial cleanup과 failed 상태로 수렴한다", async () => {
    await seedMediaMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(541),
    }, now);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    await Promise.all([
      copyJob.ref.update({
        status: "processing",
        phase: "copying",
        attempt: 3,
        leaseToken: "expired-copy-lease",
        leaseExpiresAt: Timestamp.fromMillis(now.getTime() - 1),
        nextAttemptAt: Timestamp.fromMillis(now.getTime() - 1),
      }),
      bundle.ref.update({state: "copying"}),
    ]);
    const fake = fakeEvidenceStorage();
    const source = copyJob.data().sourceObjects[0];
    await fake.storage.copy({
      source,
      destinationBucket: "evidence-bucket",
      destinationPath: `${bundle.id}/g0/${source.attachmentID}/display`,
      bundleID: bundle.id,
      attemptGeneration: 0,
    });
    assert.equal(await processMessageEvidenceCopyJob({
      jobID: copyJob.id,
      firestore: db,
      storage: fake.storage,
      readyBucket: "ready-bucket",
      evidenceBucket: "evidence-bucket",
      now,
    }), true);
    const completedJob = await copyJob.ref.get();
    assert.equal(completedJob.data()?.status, "failed");
    assert.equal(completedJob.data()?.attempt, 3);
    assert.equal((await bundle.ref.get()).data()?.state, "failed");
    assert.equal(fake.calls.copy, 1);
    assert.equal(fake.calls.deleteAttempt, 1);
    assert.equal(fake.objects.size, 0);
  });

  test("retention cleanup은 generation 일치 객체와 evidence bundle을 삭제하고 비민감 영수증만 남긴다", async () => {
    await seedMediaMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(507),
    }, now);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage();
    await processMessageEvidenceCopyJob({jobID: copyJob.id, firestore: db, storage: fake.storage, readyBucket: "ready-bucket", evidenceBucket: "evidence-bucket", now});
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    await bundle.ref.update({state: "cleanupPending"});
    const cleanupRef = db.collection("moderationEvidenceCleanupJobs").doc("cleanup-1");
    await cleanupRef.set({
      bundleID: bundle.id,
      status: "pending",
      phase: "deleting",
      attempt: 0,
      nextAttemptAt: Timestamp.fromDate(now),
      leaseToken: null,
      leaseExpiresAt: null,
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
    assert.equal(await processMessageEvidenceCleanupJob({jobID: cleanupRef.id, firestore: db, storage: fake.storage, evidenceBucket: "evidence-bucket", now}), true);
    assert.equal(fake.calls.deleteEvidence, 1);
    assert.equal(fake.objects.size, 0);
    assert.equal((await bundle.ref.get()).exists, false);
    const cleanup = await cleanupRef.get();
    assert.equal(cleanup.data()?.status, "succeeded");
    assert.equal(cleanup.data()?.phase, "completed");
    assert.equal(cleanup.data()?.evidenceObjects, undefined);
    assert.ok(cleanup.data()?.expiresAt instanceof Timestamp);
  });

  test("20회차 cleanup lease 중단은 만료 뒤 같은 시도 번호로 삭제를 재개한다", async () => {
    await seedMediaMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(542),
    }, now);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage();
    await processMessageEvidenceCopyJob({jobID: copyJob.id, firestore: db, storage: fake.storage, readyBucket: "ready-bucket", evidenceBucket: "evidence-bucket", now});
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    await bundle.ref.update({state: "deleting"});
    const cleanupRef = db.collection("moderationEvidenceCleanupJobs").doc("cleanup-final-lease");
    await cleanupRef.set({
      bundleID: bundle.id,
      status: "processing",
      phase: "deleting",
      attempt: 20,
      nextAttemptAt: Timestamp.fromMillis(now.getTime() - 1),
      leaseToken: "expired-cleanup-lease",
      leaseExpiresAt: Timestamp.fromMillis(now.getTime() - 1),
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
    assert.equal(await processMessageEvidenceCleanupJob({jobID: cleanupRef.id, firestore: db, storage: fake.storage, evidenceBucket: "evidence-bucket", now}), true);
    const completedJob = await cleanupRef.get();
    assert.equal(completedJob.data()?.status, "succeeded");
    assert.equal(completedJob.data()?.attempt, 20);
    assert.equal((await bundle.ref.get()).exists, false);
    assert.equal(fake.calls.deleteEvidence, 1);
  });

  test("retention cleanup은 attachment보다 불완전한 object manifest를 fail closed한다", async () => {
    await seedMediaMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room",
      messageID: "media-1",
      reason: "privacy",
      detail: null,
      clientRequestID: requestID(540),
    }, now);
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    await bundle.ref.update({state: "cleanupPending", evidenceObjects: []});
    const cleanupRef = db.collection("moderationEvidenceCleanupJobs").doc("cleanup-incomplete");
    await cleanupRef.set({
      bundleID: bundle.id,
      status: "pending",
      phase: "deleting",
      attempt: 0,
      nextAttemptAt: Timestamp.fromDate(now),
      leaseToken: null,
      leaseExpiresAt: null,
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    });
    const fake = fakeEvidenceStorage();
    assert.equal(await processMessageEvidenceCleanupJob({jobID: cleanupRef.id, firestore: db, storage: fake.storage, evidenceBucket: "evidence-bucket", now}), false);
    assert.equal((await bundle.ref.get()).exists, true);
    assert.equal((await bundle.ref.get()).data()?.state, "cleanupPending");
    assert.equal((await cleanupRef.get()).data()?.status, "retryPending");
    assert.equal(fake.calls.deleteEvidence, 0);
  });

  test("미디어 evidence 실패 재시작은 cleanup 완료를 요구하고 TTL 삭제 job은 재생성한다", async () => {
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
    await copyJob.ref.delete();
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

  test("메시지 기각은 같은 seq를 복원하고 Evidence를 즉시 cleanup 대기로 전환한다", async () => {
    await seedTextMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "text-1", reason: "spam", detail: "반복",
      clientRequestID: requestID(801),
    }, now);
    const incident = (await db.collection("moderationMessageIncidents").get()).docs[0];
    const result = await resolveMessageModerationService("admin-a", {
      incidentID: incident.id,
      reviewRevision: 0,
      decision: "dismissed",
      restrictedUntil: null,
      expectedCaseVersion: incident.data().caseVersion,
      expectedAccountStateVersion: null,
      reasonCode: "not-violation",
      clientRequestID: requestID(802),
    }, now, db);
    assert.equal(result.reviewState, "dismissed");
    const message = await db.collection("Rooms").doc("moderation-room").collection("Messages").doc("text-1").get();
    assert.equal(message.data()?.seq, 1);
    assert.equal(message.data()?.isDeleted, false);
    assert.equal(message.data()?.moderationVisibilityState, "visible");
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    assert.equal(bundle.data().state, "cleanupPending");
    assert.equal((await db.collection("moderationEvidenceCleanupJobs").get()).size, 1);
    const preparation = (await db.collection("moderationMessageReportPreparations").get()).docs[0].data();
    assert.equal(preparation.reason, undefined);
    assert.equal(preparation.roomID, undefined);
    assert.ok(preparation.expiresAt instanceof Timestamp);
  });

  test("신고 후 작성자가 삭제한 메시지는 관리자 기각으로 부활시키지 않는다", async () => {
    await seedTextMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "text-1", reason: "spam", detail: null,
      clientRequestID: requestID(805),
    }, now);
    await deleteChatMessageService(targetUID, null, {
      roomID: "moderation-room", messageID: "text-1", expectedSeq: 1,
      reasonCode: null, reportTargetType: null, reportTargetID: null,
      clientRequestID: requestID(806),
    }, now, db);
    const incident = (await db.collection("moderationMessageIncidents").get()).docs[0];
    const result = await resolveMessageModerationService("admin-a", {
      incidentID: incident.id, reviewRevision: 0, decision: "dismissed", restrictedUntil: null,
      expectedCaseVersion: incident.data().caseVersion, expectedAccountStateVersion: null,
      reasonCode: "not-violation", clientRequestID: requestID(807),
    }, now, db);
    assert.equal(result.messageVisibilityState, "deleted");
    const message = await db.collection("Rooms").doc("moderation-room").collection("Messages").doc("text-1").get();
    assert.equal(message.data()?.isDeleted, true);
    assert.equal(message.data()?.moderationVisibilityState, "deleted");
  });

  test("확정 위반은 moderationRemoved tombstone·위반 projection·감사를 원자적으로 남긴다", async () => {
    await seedTextMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "text-1", reason: "harassment", detail: null,
      clientRequestID: requestID(811),
    }, now);
    const incident = (await db.collection("moderationMessageIncidents").get()).docs[0];
    await resolveMessageModerationService("admin-a", {
      incidentID: incident.id, reviewRevision: 0, decision: "warningOnly", restrictedUntil: null,
      expectedCaseVersion: incident.data().caseVersion, expectedAccountStateVersion: null,
      reasonCode: "confirmed-harassment", clientRequestID: requestID(812),
    }, now, db);
    const message = await db.collection("Rooms").doc("moderation-room").collection("Messages").doc("text-1").get();
    assert.equal(message.data()?.isDeleted, true);
    assert.equal(message.data()?.deletionPresentation, "moderationRemoved");
    assert.equal(message.data()?.msg, undefined);
    const violations = await db.collection("moderationConfirmedViolations").doc(targetPrincipalID).get();
    assert.equal(violations.data()?.confirmedCount90Days, 1);
    assert.equal(violations.data()?.activeWarningCount, 1);
    assert.equal((await violations.ref.collection("incidents").get()).size, 1);
    const audit = (await db.collection("moderationAuditLogs").get()).docs[0];
    assert.equal(audit.data().action, "resolveMessageModeration");
  });

  test("계정 제재 결정은 principal과 연결 계정을 갱신하고 Evidence를 30일 보존한다", async () => {
    await seedTextMessage();
    await db.collection("moderationPrincipals").doc(targetPrincipalID).set({
      moderationStatus: "active", restrictedUntil: null, stateVersion: 1,
    });
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "text-1", reason: "illegalDangerous", detail: null,
      clientRequestID: requestID(821),
    }, now);
    const incident = (await db.collection("moderationMessageIncidents").get()).docs[0];
    await resolveMessageModerationService("admin-a", {
      incidentID: incident.id, reviewRevision: 0, decision: "temporaryRestriction",
      restrictedUntil: new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000),
      expectedCaseVersion: incident.data().caseVersion, expectedAccountStateVersion: 1,
      reasonCode: "confirmed-danger", clientRequestID: requestID(822),
    }, now, db);
    assert.equal((await db.collection("moderationPrincipals").doc(targetPrincipalID).get()).data()?.stateVersion, 2);
    assert.equal((await db.collection("moderationAccounts").doc(targetUID).get()).data()?.moderationStatus, "restricted");
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    assert.equal(bundle.data().state, "available");
    assert.equal(bundle.data().retentionClass, "sanctionAppeal30Days");
    assert.equal((await db.collection("moderationEvidenceCleanupJobs").get()).size, 0);
    assert.equal(await enqueueDueMessageEvidenceRetention(db,
      new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)), 1);
    assert.equal((await bundle.ref.get()).data()?.state, "cleanupPending");
    assert.equal((await db.collection("moderationEvidenceCleanupJobs").get()).size, 1);
  });

  test("Evidence URL은 current revision·exact generation을 검증하고 audit 성공 뒤에만 반환한다", async () => {
    await seedMediaMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "media-1", reason: "privacy", detail: null,
      clientRequestID: requestID(831),
    }, now);
    const copyJob = (await db.collection("moderationEvidenceCopyJobs").get()).docs[0];
    const fake = fakeEvidenceStorage();
    await processMessageEvidenceCopyJob({jobID: copyJob.id, firestore: db, storage: fake.storage, readyBucket: "ready-bucket", evidenceBucket: "evidence-bucket", now});
    const incident = (await db.collection("moderationMessageIncidents").get()).docs[0];
    const bundle = (await db.collection("moderationMessageEvidence").get()).docs[0];
    const evidenceObject = bundle.data().evidenceObjects[0];
    const signer = {
      metadata: async () => ({
        generation: evidenceObject.destinationGeneration,
        size: evidenceObject.bytes,
        contentType: evidenceObject.contentType,
        metadata: {
          outpickEvidenceBundleID: bundle.id,
          outpickEvidenceAttachmentID: evidenceObject.attachmentID,
          outpickEvidenceAttemptGeneration: String(bundle.data().attemptGeneration),
          outpickEvidenceSourceGeneration: evidenceObject.sourceGeneration,
        },
      }),
      sign: async (_object, issuanceID) => `https://signed.invalid/object?issuance=${issuanceID}`,
    };
    const written = [];
    const response = await issueMessageEvidenceViewURLService({
      actorUID: "admin-a",
      request: {incidentID: incident.id, reviewRevision: 0, evidenceObjectID: evidenceObject.attachmentID, objectGeneration: evidenceObject.destinationGeneration, clientRequestID: requestID(832)},
      evidenceBucket: "evidence-bucket", projectID: "outpick-test", now, firestore: db, signer,
      auditWriter: {write: async (event) => written.push(event)},
    });
    assert.match(response.url, /^https:\/\/signed\.invalid/);
    assert.equal(written[0].actorUID, "admin-a");
    assert.equal("url" in written[0], false);
    await assert.rejects(issueMessageEvidenceViewURLService({
      actorUID: "admin-a",
      request: {incidentID: incident.id, reviewRevision: 1, evidenceObjectID: evidenceObject.attachmentID, objectGeneration: evidenceObject.destinationGeneration, clientRequestID: requestID(833)},
      evidenceBucket: "evidence-bucket", projectID: "outpick-test", now, firestore: db, signer,
      auditWriter: {write: async () => {}},
    }), (error) => error?.details?.errorCode === "STALE_REVIEW_REVISION");
    await assert.rejects(issueMessageEvidenceViewURLService({
      actorUID: "admin-a",
      request: {incidentID: incident.id, reviewRevision: 0, evidenceObjectID: evidenceObject.attachmentID, objectGeneration: evidenceObject.destinationGeneration, clientRequestID: requestID(834)},
      evidenceBucket: "evidence-bucket", projectID: "outpick-test", now, firestore: db, signer,
      auditWriter: {write: async () => { throw new Error("logging unavailable"); }},
    }), /logging unavailable/);
  });

  test("메시지 목록은 direct queue query를 사용하고 상세는 current revision만 반환한다", async () => {
    await seedTextMessage();
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "text-1", reason: "spam", detail: "old-revision",
      clientRequestID: requestID(841),
    }, now);
    let incident = (await db.collection("moderationMessageIncidents").get()).docs[0];
    await resolveMessageModerationService("admin-a", {
      incidentID: incident.id, reviewRevision: 0, decision: "dismissed", restrictedUntil: null,
      expectedCaseVersion: incident.data().caseVersion, expectedAccountStateVersion: null,
      reasonCode: "dismiss", clientRequestID: requestID(842),
    }, now, db);
    await submitMessageReportService(reporterUID, {
      roomID: "moderation-room", messageID: "text-1", reason: "sexual", detail: "current-revision",
      clientRequestID: requestID(843),
    }, new Date(now.getTime() + 1_000));
    incident = await incident.ref.get();
    const listed = await listModerationReportsService({
      targetType: "message", messageQueueView: "urgent", reviewState: null,
      priorityClass: null, pageSize: 10, cursor: null,
    }, db, new Date(now.getTime() + 2_000));
    assert.equal(listed.items.length, 1);
    assert.equal(listed.items[0].reviewRevision, 1);
    const detail = await getModerationReportDetailService({
      targetType: "message", targetID: incident.id, submissionPageSize: 10, submissionCursor: null,
    }, db);
    assert.equal(detail.revision.reviewRevision, 1);
    assert.equal(detail.submissions.length, 1);
    assert.equal(detail.submissions[0].detail, "current-revision");
  });
});
