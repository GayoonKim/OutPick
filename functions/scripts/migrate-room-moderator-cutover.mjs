import {createHash} from "node:crypto";
import {readFileSync} from "node:fs";
import {applicationDefault, cert, deleteApp, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {
  cutoverPlanHash,
  joinedProjectionInventory,
  roomCutoverPlan,
  validateCutoverApply,
} from "./room-moderator-cutover-plan.mjs";

function parseNonNegativeInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`${name}은 0 이상의 정수여야 합니다.`);
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
  const projectID = values.get("--project") ?? "";
  if (!projectID) throw new Error("--project가 필요합니다.");
  const expectedRoomCount = values.has("--expected-room-count") ?
    parseNonNegativeInteger(values.get("--expected-room-count"), "--expected-room-count") : null;
  const expectedWriteCount = values.has("--expected-write-count") ?
    parseNonNegativeInteger(values.get("--expected-write-count"), "--expected-write-count") : null;
  const expectedPlanHash = values.get("--expected-plan-hash") ?? null;
  if (apply && (expectedRoomCount === null || expectedWriteCount === null || !expectedPlanHash)) {
    throw new Error("apply에는 --expected-room-count, --expected-write-count, --expected-plan-hash가 필요합니다.");
  }
  return {
    projectID,
    credentialPath: values.get("--credential") ?? null,
    expectedRoomCount,
    expectedWriteCount,
    expectedPlanHash,
    confirmation: values.get("--confirm") ?? null,
    apply,
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

function opaque(value) {
  return createHash("sha256").update(value).digest("hex").slice(0, 16);
}

function redactedBlocker(blocker) {
  const [code, identifier] = blocker.split(":", 2);
  return identifier ? `${code}:${opaque(identifier)}` : code;
}

async function loadRoomInput(firestore, roomSnapshot, joined) {
  const [members, moderationState] = await Promise.all([
    roomSnapshot.ref.collection("members").get(),
    firestore.collection("roomModerationStates").doc(roomSnapshot.id).get(),
  ]);
  const messages = [];
  for await (const message of roomSnapshot.ref.collection("Messages")
    .select("seq", "unreadMessageSeq", "type", "messageType", "serverGenerated", "roleEvent").stream()) {
    messages.push({id: message.id, ...message.data()});
  }
  return {
    room: {...roomSnapshot.data(), id: roomSnapshot.id},
    messages,
    members: members.docs.map((document) => ({...document.data(), id: document.id})),
    joined,
    moderationState: moderationState.exists ? moderationState.data() : null,
  };
}

async function loadJoinedProjections(firestore) {
  const projections = [];
  for await (const user of firestore.collection("users").select().stream()) {
    for await (const joined of user.ref.collection("joinedRooms").stream()) {
      projections.push({
        ...joined.data(),
        id: user.id,
        documentRoomID: joined.id,
      });
    }
  }
  return projections;
}

async function buildPlans(firestore) {
  const rooms = [];
  for await (const room of firestore.collection("Rooms").stream()) rooms.push(room);
  const inventory = joinedProjectionInventory(
    rooms.map((room) => room.id),
    await loadJoinedProjections(firestore),
  );
  const plans = [];
  for (const room of rooms) {
    plans.push(roomCutoverPlan(await loadRoomInput(
      firestore,
      room,
      inventory.byRoomID.get(room.id) ?? [],
    )));
  }
  return {
    plans: plans.sort((lhs, rhs) => lhs.roomID.localeCompare(rhs.roomID)),
    inventoryBlockers: inventory.blockers,
  };
}

async function applyWrites(firestore, writes) {
  for (let offset = 0; offset < writes.length; offset += 400) {
    const batch = firestore.batch();
    for (const write of writes.slice(offset, offset + 400)) {
      batch.set(firestore.doc(write.path), {...write.fields, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    }
    await batch.commit();
  }
}

const options = parseArguments(process.argv.slice(2));
const app = initializeApp({
  credential: credentialFor(options.projectID, options.credentialPath),
  projectId: options.projectID,
}, "room-moderator-cutover");

try {
  const firestore = getFirestore(app);
  const {plans, inventoryBlockers} = await buildPlans(firestore);
  const writes = plans.flatMap((plan) => plan.writes);
  const blockers = plans.flatMap((plan) => plan.blockers.map((blocker) => ({
    roomHash: opaque(plan.roomID),
    blocker: redactedBlocker(blocker),
  }))).concat(inventoryBlockers.map(({roomID, blocker}) => ({
    roomHash: opaque(roomID),
    blocker: redactedBlocker(blocker),
  })));
  const summary = {
    mode: options.apply ? "apply" : "dry-run",
    projectID: options.projectID,
    roomCount: plans.length,
    writeCount: writes.length,
    blockerCount: blockers.length,
    affectedRoomCount: plans.filter((plan) => plan.writes.length > 0).length,
    planHash: cutoverPlanHash(plans),
    blockerSamples: blockers.slice(0, 20),
  };
  console.log(JSON.stringify(summary, null, 2));

  if (!options.apply) {
    console.log("dry-run 완료: Firestore를 변경하지 않았습니다.");
  } else {
    validateCutoverApply(options, summary);
    await applyWrites(firestore, writes);
    console.log(JSON.stringify({applied: true, writeCount: writes.length}));
  }
} finally {
  await deleteApp(app);
}
