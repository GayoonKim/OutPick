import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {applicationDefault, cert, initializeApp} from "firebase-admin/app";
import {FieldPath, getFirestore} from "firebase-admin/firestore";

function parseArguments(argv) {
  let projectID = null;
  let credentialPath = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--project") {
      projectID = argv[index + 1] ?? null;
      index += 1;
    } else if (argument === "--credential") {
      credentialPath = argv[index + 1] ?? null;
      index += 1;
    } else {
      throw new Error(`지원하지 않는 인자입니다: ${argument}`);
    }
  }
  if (!projectID?.trim()) throw new Error("--project 값이 필요합니다.");
  return {projectID: projectID.trim(), credentialPath};
}

function credentialFor(projectID, credentialPath) {
  if (!credentialPath) return applicationDefault();
  const serviceAccount = JSON.parse(readFileSync(credentialPath, "utf8"));
  if (serviceAccount.project_id !== projectID) {
    throw new Error("service account project와 --project가 일치하지 않습니다.");
  }
  return cert(serviceAccount);
}

function positiveRevision(value) {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 ? value : null;
}

function nonNegativeRevision(value) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function nonNegativeSequence(value) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function validTimestamp(value) {
  if (typeof value?.toMillis !== "function") return false;
  const milliseconds = value.toMillis();
  return Number.isFinite(milliseconds) && milliseconds >= 0;
}

function opaqueID(value) {
  return createHash("sha256").update(value).digest("hex").slice(0, 16);
}

function cleanupJobID(roomID, messageID) {
  return createHash("sha256").update(`${roomID}:${messageID}`).digest("hex");
}

function hasManagedStorageTarget(roomID, messageID, attachments) {
  if (!Array.isArray(attachments)) return false;
  const expected = `rooms/${roomID}/messages/${messageID}`;
  return attachments.some((attachment) => {
    if (!attachment || typeof attachment !== "object") return false;
    return [attachment.pathThumb, attachment.pathOriginal].some((value) =>
      typeof value === "string" && (value === expected || value.startsWith(`${expected}/`))
    );
  });
}

const {projectID, credentialPath} = parseArguments(process.argv.slice(2));
const app = initializeApp({
  projectId: projectID,
  credential: credentialFor(projectID, credentialPath),
});
const firestore = getFirestore(app);

const counts = {
  roomsScanned: 0,
  deletedMessages: 0,
  revisionPresent: 0,
  revisionMissing: 0,
  invalidMessagePath: 0,
  roomIDMismatch: 0,
  messageIDMismatch: 0,
  invalidMissingSequence: 0,
  duplicateMissingSequence: 0,
  invalidMissingDeletedAt: 0,
  missingWithAttachments: 0,
  missingWithManagedStorageTarget: 0,
  cleanupJobPresent: 0,
  cleanupJobMissing: 0,
  cleanupJobInvalidStatus: 0,
  cleanupJobInvalidAttempt: 0,
  cleanupJobAttemptMin: null,
  cleanupJobAttemptMax: null,
  remainingReplyPreviewReferences: 0,
  remainingMediaIndexReferences: 0,
  cleanupProbeFailures: 0,
  replyPreviewProbeFailures: 0,
  mediaIndexProbeFailures: 0,
  deletionDeliveryJobs: 0,
  deletionDeliveryJobsInvalidStatus: 0,
  deletionDeliveryJobsInvalidEventKind: 0,
};
const cleanupJobStatusCounts = {};
const cleanupJobErrorCodeCounts = {};
const cleanupProbeErrorCodeCounts = {};
const cleanupProbeErrorNameCounts = {};
const deletionDeliveryJobStatusCounts = {};
const deletionDeliveryJobEventKindCounts = {};
const missingByRoom = new Map();
const deletedRevisionByRoom = new Map();
const headByRoom = new Map();
const missingAuditItems = [];

const rooms = firestore.collection("Rooms").select("messageDeletionRevision");
for await (const room of rooms.stream()) {
  counts.roomsScanned += 1;
  const roomID = room.id;
  headByRoom.set(roomID, nonNegativeRevision(room.get("messageDeletionRevision")));
  const deletedMessages = room.ref.collection("Messages")
    .where("isDeleted", "==", true)
    .select("roomID", "ID", "seq", "deletionRevision", "deletedAt", "attachments");
  for await (const document of deletedMessages.stream()) {
    const segments = document.ref.path.split("/");
    if (segments.length !== 4 || segments[0] !== "Rooms" || segments[2] !== "Messages") {
      counts.invalidMessagePath += 1;
      continue;
    }
    counts.deletedMessages += 1;
    const data = document.data();
    const canonicalRoomID = segments[1];
    const canonicalMessageID = segments[3];
    if (data.roomID !== canonicalRoomID) {
      counts.roomIDMismatch += 1;
    }
    if (data.ID !== canonicalMessageID) {
      counts.messageIDMismatch += 1;
    }
    const revision = positiveRevision(data.deletionRevision);
    const roomRevisionState = deletedRevisionByRoom.get(canonicalRoomID) ?? {
      presentCount: 0,
      maxPresentRevision: 0,
      missingSequences: new Set(),
      invalidMissingSequence: 0,
      duplicateMissingSequence: 0,
      invalidMissingDeletedAt: 0,
      missingWithAttachments: 0,
      missingWithManagedStorageTarget: 0,
      cleanupJobPresent: 0,
      cleanupJobMissing: 0,
      cleanupJobInvalidStatus: 0,
      cleanupJobInvalidAttempt: 0,
      cleanupJobAttemptMin: null,
      cleanupJobAttemptMax: null,
      cleanupJobStatusCounts: {},
      cleanupJobErrorCodeCounts: {},
    };
    deletedRevisionByRoom.set(canonicalRoomID, roomRevisionState);
    if (revision !== null) {
      counts.revisionPresent += 1;
      roomRevisionState.presentCount += 1;
      roomRevisionState.maxPresentRevision = Math.max(roomRevisionState.maxPresentRevision, revision);
      continue;
    }
    counts.revisionMissing += 1;
    missingByRoom.set(canonicalRoomID, (missingByRoom.get(canonicalRoomID) ?? 0) + 1);
    const sequence = nonNegativeSequence(data.seq);
    if (sequence === null) {
      counts.invalidMissingSequence += 1;
      roomRevisionState.invalidMissingSequence += 1;
    } else if (roomRevisionState.missingSequences.has(sequence)) {
      counts.duplicateMissingSequence += 1;
      roomRevisionState.duplicateMissingSequence += 1;
    } else {
      roomRevisionState.missingSequences.add(sequence);
    }
    if (!validTimestamp(data.deletedAt)) {
      counts.invalidMissingDeletedAt += 1;
      roomRevisionState.invalidMissingDeletedAt += 1;
    }
    const attachments = Array.isArray(data.attachments) ? data.attachments : [];
    if (attachments.length > 0) {
      counts.missingWithAttachments += 1;
      roomRevisionState.missingWithAttachments += 1;
    }
    if (hasManagedStorageTarget(canonicalRoomID, canonicalMessageID, attachments)) {
      counts.missingWithManagedStorageTarget += 1;
      roomRevisionState.missingWithManagedStorageTarget += 1;
    }
    missingAuditItems.push({
      roomRef: room.ref,
      messageID: canonicalMessageID,
      cleanupRef: firestore.collection("chatMessageCleanupJobs")
        .doc(cleanupJobID(canonicalRoomID, canonicalMessageID)),
      revisionState: roomRevisionState,
    });
  }
}

function recordProbeFailure(error, kind) {
  counts.cleanupProbeFailures += 1;
  counts[kind] += 1;
  const code = typeof error?.code === "string" || typeof error?.code === "number" ?
    String(error.code) : "unknown";
  const name = typeof error?.name === "string" ? error.name : "unknown";
  cleanupProbeErrorCodeCounts[code] = (cleanupProbeErrorCodeCounts[code] ?? 0) + 1;
  cleanupProbeErrorNameCounts[name] = (cleanupProbeErrorNameCounts[name] ?? 0) + 1;
}

for (const item of missingAuditItems) {
  try {
    const replyReferences = await item.roomRef.collection("Messages")
      .where("replyPreview.messageID", "==", item.messageID)
      .orderBy("__name__")
      .limit(1)
      .select(FieldPath.documentId())
      .get();
    counts.remainingReplyPreviewReferences += replyReferences.size;
  } catch (error) {
    recordProbeFailure(error, "replyPreviewProbeFailures");
  }
  try {
    const mediaReferences = await item.roomRef.collection("mediaIndex")
      .where("messageID", "==", item.messageID)
      .limit(1)
      .select(FieldPath.documentId())
      .get();
    counts.remainingMediaIndexReferences += mediaReferences.size;
  } catch (error) {
    recordProbeFailure(error, "mediaIndexProbeFailures");
  }
}

if (missingAuditItems.length > 0) {
  const cleanupSnapshots = await firestore.getAll(...missingAuditItems.map((item) => item.cleanupRef));
  cleanupSnapshots.forEach((snapshot, index) => {
    const item = missingAuditItems[index];
    if (snapshot.exists) {
      counts.cleanupJobPresent += 1;
      item.revisionState.cleanupJobPresent += 1;
      const status = snapshot.get("status");
      if (typeof status === "string" && status.length > 0) {
        cleanupJobStatusCounts[status] = (cleanupJobStatusCounts[status] ?? 0) + 1;
        item.revisionState.cleanupJobStatusCounts[status] =
          (item.revisionState.cleanupJobStatusCounts[status] ?? 0) + 1;
      } else {
        counts.cleanupJobInvalidStatus += 1;
        item.revisionState.cleanupJobInvalidStatus += 1;
      }
      const errorCode = snapshot.get("lastErrorCode");
      if (typeof errorCode === "string" && errorCode.length > 0) {
        cleanupJobErrorCodeCounts[errorCode] =
          (cleanupJobErrorCodeCounts[errorCode] ?? 0) + 1;
        item.revisionState.cleanupJobErrorCodeCounts[errorCode] =
          (item.revisionState.cleanupJobErrorCodeCounts[errorCode] ?? 0) + 1;
      }
      const attempt = snapshot.get("attempt");
      if (typeof attempt === "number" && Number.isSafeInteger(attempt) && attempt >= 0) {
        counts.cleanupJobAttemptMin = counts.cleanupJobAttemptMin === null ?
          attempt : Math.min(counts.cleanupJobAttemptMin, attempt);
        counts.cleanupJobAttemptMax = counts.cleanupJobAttemptMax === null ?
          attempt : Math.max(counts.cleanupJobAttemptMax, attempt);
        item.revisionState.cleanupJobAttemptMin =
          item.revisionState.cleanupJobAttemptMin === null ?
            attempt : Math.min(item.revisionState.cleanupJobAttemptMin, attempt);
        item.revisionState.cleanupJobAttemptMax =
          item.revisionState.cleanupJobAttemptMax === null ?
            attempt : Math.max(item.revisionState.cleanupJobAttemptMax, attempt);
      } else {
        counts.cleanupJobInvalidAttempt += 1;
        item.revisionState.cleanupJobInvalidAttempt += 1;
      }
    } else {
      counts.cleanupJobMissing += 1;
      item.revisionState.cleanupJobMissing += 1;
    }
  });
}

const deletionDeliveryJobs = firestore.collection("chatMessageDeletionDeliveryJobs")
  .select("status", "eventKind");
for await (const document of deletionDeliveryJobs.stream()) {
  counts.deletionDeliveryJobs += 1;
  const status = document.get("status");
  if (typeof status === "string" && status.length > 0) {
    deletionDeliveryJobStatusCounts[status] =
      (deletionDeliveryJobStatusCounts[status] ?? 0) + 1;
  } else {
    counts.deletionDeliveryJobsInvalidStatus += 1;
  }
  const eventKind = document.get("eventKind");
  if (typeof eventKind === "string" && eventKind.length > 0) {
    deletionDeliveryJobEventKindCounts[eventKind] =
      (deletionDeliveryJobEventKindCounts[eventKind] ?? 0) + 1;
  } else {
    counts.deletionDeliveryJobsInvalidEventKind += 1;
  }
}

const affectedRooms = [];
for (const [roomID, missingCount] of [...missingByRoom].sort(([lhs], [rhs]) => lhs.localeCompare(rhs))) {
  const revisionState = deletedRevisionByRoom.get(roomID);
  affectedRooms.push({
    roomOpaqueID: opaqueID(roomID),
    missingCount,
    roomExists: headByRoom.has(roomID),
    currentHead: headByRoom.get(roomID) ?? null,
    existingRevisionCount: revisionState?.presentCount ?? 0,
    maxExistingRevision: revisionState?.maxPresentRevision ?? 0,
    invalidMissingSequence: revisionState?.invalidMissingSequence ?? 0,
    duplicateMissingSequence: revisionState?.duplicateMissingSequence ?? 0,
    invalidMissingDeletedAt: revisionState?.invalidMissingDeletedAt ?? 0,
    missingWithAttachments: revisionState?.missingWithAttachments ?? 0,
    missingWithManagedStorageTarget: revisionState?.missingWithManagedStorageTarget ?? 0,
    cleanupJobPresent: revisionState?.cleanupJobPresent ?? 0,
    cleanupJobMissing: revisionState?.cleanupJobMissing ?? 0,
    cleanupJobInvalidStatus: revisionState?.cleanupJobInvalidStatus ?? 0,
    cleanupJobInvalidAttempt: revisionState?.cleanupJobInvalidAttempt ?? 0,
    cleanupJobAttemptMin: revisionState?.cleanupJobAttemptMin ?? null,
    cleanupJobAttemptMax: revisionState?.cleanupJobAttemptMax ?? null,
    cleanupJobStatusCounts: revisionState?.cleanupJobStatusCounts ?? {},
    cleanupJobErrorCodeCounts: revisionState?.cleanupJobErrorCodeCounts ?? {},
  });
}

const deletedRoomSummaries = [];
let roomsWithRevisionHeadMismatch = 0;
for (const [roomID, revisionState] of [...deletedRevisionByRoom]
  .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))) {
  const currentHead = headByRoom.get(roomID) ?? null;
  const missingCount = missingByRoom.get(roomID) ?? 0;
  const revisionHeadMatches = currentHead !== null && missingCount === 0 &&
    revisionState.maxPresentRevision === currentHead;
  if (!revisionHeadMatches) roomsWithRevisionHeadMismatch += 1;
  deletedRoomSummaries.push({
    roomOpaqueID: opaqueID(roomID),
    deletedMessageCount: revisionState.presentCount + missingCount,
    revisionPresent: revisionState.presentCount,
    revisionMissing: missingCount,
    maxPresentRevision: revisionState.maxPresentRevision,
    currentHead,
    revisionHeadMatches,
  });
}

console.log(JSON.stringify({
  mode: "read-only",
  projectID,
  ...counts,
  replyPreviewReferenceCountComplete: counts.replyPreviewProbeFailures === 0,
  mediaIndexReferenceCountComplete: counts.mediaIndexProbeFailures === 0,
  cleanupJobStatusCounts,
  cleanupJobErrorCodeCounts,
  cleanupProbeErrorCodeCounts,
  cleanupProbeErrorNameCounts,
  deletionDeliveryJobStatusCounts,
  deletionDeliveryJobEventKindCounts,
  affectedRoomCount: affectedRooms.length,
  affectedRooms,
  roomsWithDeletedMessages: deletedRoomSummaries.length,
  roomsWithRevisionHeadMismatch,
  deletedRoomSummaries,
}, null, 2));
console.log("읽기 전용 감사 완료: Firestore·Storage 데이터를 변경하지 않았습니다.");
