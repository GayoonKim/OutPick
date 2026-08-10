import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {
  assertPlatformAdminOperationGate,
  platformAdminProvider,
} from "../lib/moderation/admin/platformAdminOperations.js";

function parsePositiveInteger(value, option) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${option} 값이 올바르지 않습니다.`);
  }
  return parsed;
}

function parseArguments(values) {
  const result = {
    projectID: null,
    operation: "audit",
    provider: null,
    apply: false,
    confirmation: null,
    expectedAuthCount: null,
    expectedProviderCount: null,
  };
  for (let index = 0; index < values.length; index += 1) {
    const option = values[index];
    if (option === "--apply") {
      result.apply = true;
      continue;
    }
    const value = values[index + 1];
    if (!value) throw new Error(`${option} 값이 필요합니다.`);
    index += 1;
    if (option === "--project") result.projectID = value;
    else if (option === "--action") result.operation = value;
    else if (option === "--provider") result.provider = value;
    else if (option === "--confirm-production") result.confirmation = value;
    else if (option === "--expected-auth-count") {
      result.expectedAuthCount = parsePositiveInteger(value, option);
    } else if (option === "--expected-provider-count") {
      result.expectedProviderCount = parsePositiveInteger(value, option);
    } else throw new Error(`지원하지 않는 option입니다: ${option}`);
  }
  if (!result.projectID) throw new Error("--project가 필요합니다.");
  if (!["audit", "grant", "revoke"].includes(result.operation)) {
    throw new Error("--action 값이 올바르지 않습니다.");
  }
  if (result.operation !== "audit" && !["google", "kakao"].includes(result.provider)) {
    throw new Error("grant/revoke에는 --provider google|kakao가 필요합니다.");
  }
  return result;
}

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

const options = parseArguments(process.argv.slice(2));
const app = initializeApp({
  credential: applicationDefault(),
  projectId: options.projectID,
}, "platform-admin-operations");

try {
  const auth = getAuth(app);
  const firestore = getFirestore(app);
  const users = await listAllUsers(auth);
  const recognized = users.map((user) => ({
    user,
    provider: platformAdminProvider(
      user.uid,
      user.providerData.map((entry) => entry.providerId),
    ),
  })).filter((entry) => entry.provider !== null);
  const snapshots = await Promise.all(recognized.map(async (entry) => {
    const [account, moderation, brandAdmin, platformAdmin] = await Promise.all([
      firestore.collection("users").doc(entry.user.uid).get(),
      firestore.collection("moderationAccounts").doc(entry.user.uid).get(),
      firestore.collection("brandAdmins").doc(entry.user.uid).get(),
      firestore.collection("platformAdmins").doc(entry.user.uid).get(),
    ]);
    return {
      ...entry,
      eligible: account.get("accountStatus") === "active" &&
        moderation.get("moderationStatus") === "active" &&
        typeof moderation.get("moderationPrincipalID") === "string",
      brandAdmin: brandAdmin.get("isActive") === true,
      platformAdmin: platformAdmin.get("isActive") === true &&
        !(platformAdmin.get("revokedAt") instanceof Timestamp),
    };
  }));
  const providers = Object.fromEntries(["google", "kakao"].map((provider) => {
    const matching = snapshots.filter((entry) => entry.provider === provider);
    return [provider, {
      authCount: matching.length,
      eligibleActiveCount: matching.filter((entry) => entry.eligible).length,
      activeBrandAdminCount: matching.filter((entry) => entry.brandAdmin).length,
      activePlatformAdminCount: matching.filter((entry) => entry.platformAdmin).length,
    }];
  }));
  console.log(JSON.stringify({
    mode: options.apply ? "apply" : "dry-run",
    projectID: options.projectID,
    authUserCount: users.length,
    unrecognizedProviderCount: users.length - recognized.length,
    providers,
  }, null, 2));

  const selected = options.provider ? snapshots.filter(
    (entry) => entry.provider === options.provider,
  ) : [];
  assertPlatformAdminOperationGate({
    projectID: options.projectID,
    operation: options.operation,
    apply: options.apply,
    confirmation: options.confirmation,
    expectedAuthCount: options.expectedAuthCount,
    actualAuthCount: users.length,
    expectedProviderCount: options.expectedProviderCount,
    actualProviderCount: selected.length,
  });
  if (!options.apply) {
    console.log("dry-run 완료: platformAdmins를 변경하지 않았습니다.");
  } else {
    const target = selected[0];
    if (!target?.eligible) {
      throw new Error("선택 계정이 active account/moderation 조건을 만족하지 않습니다.");
    }
    const reference = firestore.collection("platformAdmins").doc(target.user.uid);
    const result = await firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const currentlyActive = snapshot.get("isActive") === true &&
        !(snapshot.get("revokedAt") instanceof Timestamp);
      const shouldBeActive = options.operation === "grant";
      if (currentlyActive === shouldBeActive) {
        return {changed: false, isActive: currentlyActive};
      }
      const now = Timestamp.now();
      transaction.set(reference, {
        schemaVersion: 1,
        isActive: shouldBeActive,
        createdAt: snapshot.get("createdAt") instanceof Timestamp ?
          snapshot.get("createdAt") : now,
        updatedAt: now,
        revokedAt: shouldBeActive ? null : now,
      });
      return {changed: true, isActive: shouldBeActive};
    });
    console.log(JSON.stringify({applied: true, ...result}));
  }
} finally {
  await deleteApp(app);
}
