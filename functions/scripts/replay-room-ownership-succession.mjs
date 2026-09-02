import {deleteApp, getApps} from "firebase-admin/app";

const PRODUCTION_PROJECT_ID = "outpick-664ae";
const PRODUCTION_CONFIRMATION = "REPLAY_ROOM_OWNERSHIP_SUCCESSION";

function value(arguments_, name) {
  const index = arguments_.indexOf(name);
  return index >= 0 ? arguments_[index + 1] : null;
}

function parseArguments(arguments_) {
  const projectID = value(arguments_, "--project");
  const jobID = value(arguments_, "--job");
  const roomID = value(arguments_, "--room");
  const expectedTargetUID = value(arguments_, "--expected-target-uid");
  if (!projectID) throw new Error("--project가 필요합니다.");
  if (!jobID || jobID.includes("/")) throw new Error("유효한 --job이 필요합니다.");
  if (!roomID || roomID.includes("/")) throw new Error("재처리할 실패 방의 --room이 필요합니다.");
  if (!expectedTargetUID || expectedTargetUID.includes("/")) {
    throw new Error("--expected-target-uid가 필요합니다.");
  }
  return {
    projectID,
    jobID,
    roomID,
    expectedTargetUID,
    apply: arguments_.includes("--apply"),
    confirmation: value(arguments_, "--confirm"),
  };
}

const options = parseArguments(process.argv.slice(2));
if (options.apply && options.projectID === PRODUCTION_PROJECT_ID &&
    options.confirmation !== PRODUCTION_CONFIRMATION) {
  throw new Error(`Production replay에는 --confirm ${PRODUCTION_CONFIRMATION}가 필요합니다.`);
}

process.env.GCLOUD_PROJECT = options.projectID;
process.env.GOOGLE_CLOUD_PROJECT = options.projectID;

const [{db}, sweep, worker] = await Promise.all([
  import("../lib/core/firebase.js"),
  import("../lib/chat/moderation/roomSuccessionJobs.js"),
  import("../lib/chat/moderation/roomMembershipSweepFunctions.js"),
]);

try {
  const ref = db.collection("roomOwnershipSuccessionJobs").doc(options.jobID);
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new Error("승계 job을 찾지 못했습니다.");
  const room = await ref.collection("roomSuccessionAttempts").doc(options.roomID).get();
  if (!room.exists) throw new Error("방별 승계 작업을 찾지 못했습니다.");
  const summary = {
    mode: options.apply ? "apply" : "dry-run",
    projectID: options.projectID,
    jobID: options.jobID,
    targetUID: snapshot.get("targetUID"),
    cause: snapshot.get("cause"),
    roomID: options.roomID,
    status: room.get("status"),
    generation: room.get("generation"),
    attempt: room.get("attempt"),
    lastErrorCode: room.get("lastErrorCode") ?? null,
  };
  console.log(JSON.stringify(summary, null, 2));
  if (summary.targetUID !== options.expectedTargetUID) {
    throw new Error("실제 targetUID가 --expected-target-uid와 다릅니다.");
  }
  if (summary.status !== "failed") throw new Error("failed job만 수동 replay할 수 있습니다.");
  if (!options.apply) {
    console.log("dry-run 완료: --apply가 없어 Firestore를 변경하지 않았습니다.");
  } else {
    const replayed = await sweep.replayFailedRoomOwnershipSuccessionJob(options.jobID, options.roomID, options.expectedTargetUID, db);
    if (!replayed) throw new Error("승계 job replay 상태 전이가 실패했습니다.");
    await worker.processRoomOwnershipSuccessionAndSchedule(options.jobID);
    console.log(JSON.stringify({applied: true, jobID: options.jobID}));
  }
} finally {
  await Promise.all(getApps().map((app) => deleteApp(app)));
}
