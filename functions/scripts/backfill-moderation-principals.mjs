import {execFileSync} from "node:child_process";
import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {
  assertExpectedProductionCounts,
  buildBackfillCounts,
  kakaoSubjectCandidate,
  parseBackfillArguments,
  resolveBackfillIdentity,
} from "../lib/moderation/backfill.js";
import {bindModerationPrincipal} from "../lib/moderation/state.js";

async function listAllUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

function secretValue(projectID, secretName) {
  const value = execFileSync("gcloud", [
    "secrets", "versions", "access", "latest",
    `--project=${projectID}`,
    `--secret=${secretName}`,
  ], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }).trim();
  if (!value) throw new Error("Secret 값이 비어 있습니다.");
  return value;
}

const options = parseBackfillArguments(process.argv.slice(2));
const {projectID, apply} = options;
const app = initializeApp({
  credential: applicationDefault(),
  projectId: projectID,
}, "moderation-principal-backfill");

try {
  const auth = getAuth(app);
  const firestore = getFirestore(app);
  const users = await listAllUsers(auth);
  const needsKakaoLookup = users.some(
    (user) => kakaoSubjectCandidate(user.uid) !== null,
  );
  const kakaoAdminKey = needsKakaoLookup ?
    secretValue(projectID, options.kakaoAdminSecretName) : null;
  const resolved = [];
  const resolutions = [];

  for (const user of users) {
    const resolution = await resolveBackfillIdentity(user, kakaoAdminKey);
    resolutions.push(resolution);
    if (resolution.identity) {
      resolved.push({uid: user.uid, identity: resolution.identity});
    }
  }

  const counts = buildBackfillCounts(resolutions);
  const summary = {
    mode: apply ? "apply" : "dry-run",
    projectID,
    ...counts,
  };
  console.log(JSON.stringify(summary, null, 2));

  if (!apply) {
    console.log("dry-run 완료: Firestore를 변경하지 않았습니다.");
  } else {
    if (counts.unresolvedCount > 0) {
      throw new Error("불명확 provider 계정이 있어 backfill을 중단합니다.");
    }
    assertExpectedProductionCounts(options, counts);
    const secret = secretValue(projectID, options.hmacSecretName);
    for (const entry of resolved) {
      await bindModerationPrincipal(
        entry.uid,
        entry.identity,
        secret,
        new Date(),
        [],
        firestore,
      );
    }
    console.log(JSON.stringify({applied: true, processedCount: counts.resolvedCount}));
  }
} finally {
  await deleteApp(app);
}
