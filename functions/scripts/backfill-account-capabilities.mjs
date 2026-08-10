import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";

const PRODUCTION_PROJECT_ID = "outpick-664ae";
const PRODUCTION_CONFIRMATION = "APPLY_ACCOUNT_CAPABILITY_V2";

function parseArguments(arguments_) {
  const value = (name) => {
    const index = arguments_.indexOf(name);
    return index >= 0 ? arguments_[index + 1] : null;
  };
  const projectID = value("--project");
  const expectedTotalText = value("--expected-total");
  const expectedTotal = expectedTotalText === null ? null : Number(expectedTotalText);
  if (!projectID) throw new Error("--project가 필요합니다.");
  if (expectedTotal !== null && (!Number.isInteger(expectedTotal) || expectedTotal < 0)) {
    throw new Error("--expected-total은 0 이상의 정수여야 합니다.");
  }
  return {
    projectID,
    apply: arguments_.includes("--apply"),
    confirmation: value("--confirm"),
    expectedTotal,
  };
}

function normalizedAccountStatus(value) {
  return value === "active" || value === "deletionPending" ? value : null;
}

const options = parseArguments(process.argv.slice(2));
if (options.apply && options.projectID === PRODUCTION_PROJECT_ID &&
  (options.confirmation !== PRODUCTION_CONFIRMATION || options.expectedTotal === null)) {
  throw new Error(
    `Production apply에는 --confirm ${PRODUCTION_CONFIRMATION}와 --expected-total이 필요합니다.`,
  );
}

const app = initializeApp({
  credential: applicationDefault(),
  projectId: options.projectID,
}, "account-capability-v2-backfill");

try {
  const firestore = getFirestore(app);
  const [users, projections] = await Promise.all([
    firestore.collection("users").get(),
    firestore.collection("moderationAccounts").get(),
  ]);
  const usersByID = new Map(users.docs.map((document) => [document.id, document.data()]));
  const updates = [];
  let unresolvedCount = 0;
  let alreadyCurrentCount = 0;
  let activeCount = 0;
  let deletionPendingCount = 0;

  for (const projection of projections.docs) {
    const user = usersByID.get(projection.id);
    const accountStatus = normalizedAccountStatus(user?.accountStatus);
    if (!accountStatus) {
      unresolvedCount += 1;
      continue;
    }
    if (accountStatus === "active") activeCount += 1;
    else deletionPendingCount += 1;
    const data = projection.data();
    if (data.schemaVersion === 2 && data.accountStatus === accountStatus) {
      alreadyCurrentCount += 1;
    } else {
      updates.push({reference: projection.ref, accountStatus});
    }
  }
  const missingProjectionCount = users.docs.filter(
    (user) => !projections.docs.some((projection) => projection.id === user.id),
  ).length;
  const summary = {
    mode: options.apply ? "apply" : "dry-run",
    projectID: options.projectID,
    userCount: users.size,
    projectionCount: projections.size,
    activeCount,
    deletionPendingCount,
    updateCount: updates.length,
    alreadyCurrentCount,
    unresolvedCount,
    missingProjectionCount,
  };
  console.log(JSON.stringify(summary, null, 2));

  if (unresolvedCount > 0 || missingProjectionCount > 0) {
    throw new Error("users와 moderationAccounts 상태가 완전하게 대응하지 않습니다.");
  }
  if (options.expectedTotal !== null && projections.size !== options.expectedTotal) {
    throw new Error("실제 projection 수가 --expected-total과 다릅니다.");
  }
  if (options.apply) {
    const batch = firestore.batch();
    for (const update of updates) {
      batch.update(update.reference, {
        schemaVersion: 2,
        accountStatus: update.accountStatus,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    console.log(JSON.stringify({applied: true, updatedCount: updates.length}));
  } else {
    console.log("dry-run 완료: Firestore를 변경하지 않았습니다.");
  }
} finally {
  await deleteApp(app);
}
