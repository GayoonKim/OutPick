import type {Auth, UserRecord} from "firebase-admin/auth";
import type {ResetRequest} from "./firestoreReset.js";

const defaultIDPrefix = "uitest-";
const pageSize = 1000;

export interface AuthResetResult {
  readonly matchedAuthUserIDs: string[];
  readonly deletedAuthUserCount: number;
}

export async function resetAuthTestUsers(
  auth: Auth,
  request: ResetRequest
): Promise<AuthResetResult> {
  const matchedAuthUserIDs = await listResettableAuthUserIDs(auth, request);

  if (request.dryRun === true || matchedAuthUserIDs.length === 0) {
    return {
      matchedAuthUserIDs,
      deletedAuthUserCount: 0
    };
  }

  const result = await auth.deleteUsers(matchedAuthUserIDs);
  if (result.failureCount > 0) {
    throw new Error(
      `Auth user 삭제 실패: ${JSON.stringify(result.errors)}`
    );
  }

  return {
    matchedAuthUserIDs,
    deletedAuthUserCount: result.successCount
  };
}

async function listResettableAuthUserIDs(
  auth: Auth,
  request: ResetRequest
): Promise<string[]> {
  const matchedUserIDs: string[] = [];
  let pageToken: string | undefined;

  do {
    const result = await auth.listUsers(pageSize, pageToken);
    matchedUserIDs.push(
      ...result.users
        .filter((user) => shouldResetUser(user, request.testRunId))
        .map((user) => user.uid)
    );
    pageToken = result.pageToken;
  } while (pageToken !== undefined);

  return matchedUserIDs;
}

function shouldResetUser(
  user: UserRecord,
  testRunId: string | undefined
): boolean {
  if (user.uid.startsWith(defaultIDPrefix)) {
    return true;
  }

  const normalizedTestRunId = testRunId?.trim() ?? "";
  return normalizedTestRunId.length > 0 && user.uid.includes(normalizedTestRunId);
}
