import assert from "node:assert/strict";
import {after, beforeEach, describe, test} from "node:test";
import {Timestamp} from "../functions/node_modules/firebase-admin/lib/firestore/index.js";
import {db} from "../functions/lib/core/firebase.js";
import {
  submitUserReportService,
} from "../functions/lib/moderation/reports/service.js";
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
