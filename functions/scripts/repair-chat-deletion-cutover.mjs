import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {applicationDefault, cert, initializeApp} from "firebase-admin/app";
import {FieldPath, Timestamp, getFirestore} from "firebase-admin/firestore";
import {
  APPLY_CONFIRMATION,
  buildRevisionAssignments,
  opaqueRoomID,
  validateApplyGate,
} from "./chat-deletion-cutover-plan.mjs";

const OPERATIONS = new Set(["resume-cleanup", "backfill-revisions"]);

function parseInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`${name}은 0 이상의 정수여야 합니다.`);
  }
  return parsed;
}

function parseArguments(argv) {
  const values = new Map();
  let apply = false;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") {
      apply = true;
      continue;
    }
    if (!argument.startsWith("--")) throw new Error(`지원하지 않는 인자입니다: ${argument}`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`${argument} 값이 필요합니다.`);
    values.set(argument, value);
    index += 1;
  }
  const operation = values.get("--operation");
  if (!OPERATIONS.has(operation)) {
    throw new Error("--operation은 resume-cleanup 또는 backfill-revisions여야 합니다.");
  }
  return {
    projectID: values.get("--project") ?? "",
    credentialPath: values.get("--credential") ?? null,
    operation,
    expectedRoomHash: values.get("--expected-room-hash") ?? "",
    expectedCount: parseInteger(values.get("--expected-count"), "--expected-count"),
    expectedHead: parseInteger(values.get("--expected-head"), "--expected-head"),
    apply,
    confirmation: values.get("--confirm") ?? null,
  };
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

function cleanupJobID(roomID, messageID) {
  return createHash("sha256").update(`${roomID}:${messageID}`).digest("hex");
}

function validateMessageSnapshot(snapshot, roomID) {
  const data = snapshot.data();
  if (!snapshot.exists || !data || data.isDeleted !== true ||
      data.ID !== snapshot.id || data.roomID !== roomID ||
      positiveRevision(data.deletionRevision) !== null ||
      !Number.isSafeInteger(data.seq) || data.seq < 0 ||
      !(data.deletedAt instanceof Timestamp)) {
    throw new Error("legacy tombstone이 감사 시점 계약과 달라졌습니다.");
  }
  if (Array.isArray(data.attachments) && data.attachments.length > 0) {
    throw new Error("첨부가 있는 legacy tombstone은 이 보정 범위에서 처리하지 않습니다.");
  }
  return data;
}

function validateCleanupSnapshot(snapshot, roomID, messageID, seq) {
  const data = snapshot.data();
  if (!snapshot.exists || !data || data.roomID !== roomID || data.messageID !== messageID ||
      data.expectedSeq !== seq) {
    throw new Error("cleanup job이 감사 시점 계약과 달라졌습니다.");
  }
  return data;
}

async function discoverCandidate(firestore) {
  const affected = [];
  const rooms = firestore.collection("Rooms").select("messageDeletionRevision");
  for await (const room of rooms.stream()) {
    const messages = [];
    const deleted = room.ref.collection("Messages")
      .where("isDeleted", "==", true)
      .select("ID", "roomID", "seq", "isDeleted", "deletionRevision", "deletedAt", "attachments");
    for await (const message of deleted.stream()) {
      if (positiveRevision(message.get("deletionRevision")) === null) messages.push(message);
    }
    if (messages.length > 0) {
      affected.push({
        roomRef: room.ref,
        roomID: room.id,
        head: nonNegativeRevision(room.get("messageDeletionRevision")),
        messages,
      });
    }
  }
  if (affected.length !== 1) {
    throw new Error(`영향 방은 정확히 1개여야 합니다. actual=${affected.length}`);
  }
  return affected[0];
}

async function readTransactionSnapshots(transaction, candidate, firestore) {
  const room = await transaction.get(candidate.roomRef);
  const messages = [];
  const cleanupJobs = [];
  for (const original of candidate.messages) {
    const message = await transaction.get(original.ref);
    const cleanupRef = firestore.collection("chatMessageCleanupJobs")
      .doc(cleanupJobID(candidate.roomID, original.id));
    const cleanup = await transaction.get(cleanupRef);
    messages.push(message);
    cleanupJobs.push({ref: cleanupRef, snapshot: cleanup});
  }
  return {room, messages, cleanupJobs};
}

async function probeReferences(candidate) {
  let replies = 0;
  let media = 0;
  for (const message of candidate.messages) {
    const [replySnapshot, mediaSnapshot] = await Promise.all([
      candidate.roomRef.collection("Messages")
        .where("replyPreview.messageID", "==", message.id)
        .orderBy("__name__")
        .limit(1)
        .select(FieldPath.documentId())
        .get(),
      candidate.roomRef.collection("mediaIndex")
        .where("messageID", "==", message.id)
        .limit(1)
        .select(FieldPath.documentId())
        .get(),
    ]);
    replies += replySnapshot.size;
    media += mediaSnapshot.size;
  }
  return {replies, media};
}

async function resumeCleanup(firestore, candidate, options) {
  const cleanupStates = new Map();
  for (const message of candidate.messages) {
    const data = validateMessageSnapshot(message, candidate.roomID);
    const reference = firestore.collection("chatMessageCleanupJobs")
      .doc(cleanupJobID(candidate.roomID, message.id));
    const snapshot = await reference.get();
    const cleanup = validateCleanupSnapshot(snapshot, candidate.roomID, message.id, data.seq);
    cleanupStates.set(cleanup.status, (cleanupStates.get(cleanup.status) ?? 0) + 1);
  }
  if (!options.apply) return {cleanupStates: Object.fromEntries(cleanupStates), writes: 0};

  const now = Timestamp.now();
  await firestore.runTransaction(async (transaction) => {
    const snapshots = await readTransactionSnapshots(transaction, candidate, firestore);
    if (!snapshots.room.exists ||
        nonNegativeRevision(snapshots.room.get("messageDeletionRevision")) !== options.expectedHead) {
      throw new Error("Room deletion head가 apply 직전에 달라졌습니다.");
    }
    snapshots.messages.forEach((message, index) => {
      const data = validateMessageSnapshot(message, candidate.roomID);
      const cleanup = validateCleanupSnapshot(
        snapshots.cleanupJobs[index].snapshot, candidate.roomID, message.id, data.seq,
      );
      if (cleanup.status !== "failed" || cleanup.attempt !== 20) {
        throw new Error("cleanup job이 expected failed/attempt=20 상태와 다릅니다.");
      }
    });
    for (const cleanup of snapshots.cleanupJobs) {
      transaction.update(cleanup.ref, {
        status: "retryPending",
        attempt: 0,
        nextAttemptAt: now,
        leaseExpiresAt: null,
        lastErrorCode: null,
        updatedAt: now,
        expiresAt: null,
      });
    }
  });
  return {cleanupStates: Object.fromEntries(cleanupStates), writes: candidate.messages.length};
}

async function backfillRevisions(firestore, candidate, options) {
  const probes = await probeReferences(candidate);
  if (probes.replies !== 0 || probes.media !== 0) {
    throw new Error(`cleanup 잔존이 있어 backfill을 중단합니다. replies=${probes.replies}, media=${probes.media}`);
  }
  const assignments = buildRevisionAssignments(candidate.messages.map((message) => ({
    id: message.id,
    seq: validateMessageSnapshot(message, candidate.roomID).seq,
  })), options.expectedHead);
  if (!options.apply) return {assignments, probes, writes: 0};

  const now = Timestamp.now();
  await firestore.runTransaction(async (transaction) => {
    const snapshots = await readTransactionSnapshots(transaction, candidate, firestore);
    if (!snapshots.room.exists ||
        nonNegativeRevision(snapshots.room.get("messageDeletionRevision")) !== options.expectedHead) {
      throw new Error("Room deletion head가 apply 직전에 달라졌습니다.");
    }
    const byID = new Map();
    snapshots.messages.forEach((message, index) => {
      const data = validateMessageSnapshot(message, candidate.roomID);
      const cleanup = validateCleanupSnapshot(
        snapshots.cleanupJobs[index].snapshot, candidate.roomID, message.id, data.seq,
      );
      if (cleanup.status !== "completed") {
        throw new Error("cleanup이 completed가 아니어서 backfill을 중단합니다.");
      }
      byID.set(message.id, {message, data});
    });
    for (const assignment of assignments) {
      const target = byID.get(assignment.id);
      transaction.set(target.message.ref, {
        ID: assignment.id,
        roomID: candidate.roomID,
        seq: assignment.seq,
        isDeleted: true,
        deletionRevision: assignment.deletionRevision,
        deletedAt: target.data.deletedAt,
      });
    }
    transaction.update(candidate.roomRef, {
      messageDeletionRevision: options.expectedHead + assignments.length,
      updatedAt: now,
    });
  });
  return {assignments, probes, writes: assignments.length + 1};
}

const options = parseArguments(process.argv.slice(2));
const app = initializeApp({
  projectId: options.projectID,
  credential: credentialFor(options.projectID, options.credentialPath),
});
const firestore = getFirestore(app);
const candidate = await discoverCandidate(firestore);
const actual = {
  roomHash: opaqueRoomID(candidate.roomID),
  count: candidate.messages.length,
  head: candidate.head,
};
validateApplyGate(options, actual);

const result = options.operation === "resume-cleanup" ?
  await resumeCleanup(firestore, candidate, options) :
  await backfillRevisions(firestore, candidate, options);
console.log(JSON.stringify({
  mode: options.apply ? "apply" : "dry-run",
  operation: options.operation,
  projectID: options.projectID,
  roomOpaqueID: actual.roomHash,
  missingCount: actual.count,
  currentHead: actual.head,
  plannedToRevision: options.expectedHead + options.expectedCount,
  cleanupStates: result.cleanupStates ?? null,
  probeCounts: result.probes ?? null,
  plannedAssignments: result.assignments?.length ?? 0,
  writes: result.writes,
  deliveryOutboxWrites: 0,
}, null, 2));
if (!options.apply) {
  console.log(`dry-run 완료: apply에는 --apply --confirm ${APPLY_CONFIRMATION}가 필요합니다.`);
}
