import type {Auth} from "firebase-admin/auth";
import {FieldValue} from "firebase-admin/firestore";

export const lookbookTestIDs = {
  brandID: "uitest-brand",
  seasonID: "uitest-season",
  postID: "uitest-post",
  currentUserID: "uitest-user",
  authorUserID: "uitest-author",
  commenterUserID: "uitest-commenter",
  replierUserID: "uitest-replier"
} as const;

export const lookbookTestEmails = {
  currentUserEmail: "uitest@outpick.local",
  authorUserEmail: "uitest-author@outpick.local",
  commenterUserEmail: "uitest-commenter@outpick.local",
  replierUserEmail: "uitest-replier@outpick.local"
} as const;

export async function upsertAuthUser(
  auth: Auth,
  uid: string,
  email: string,
  password: string,
  displayName: string
): Promise<void> {
  try {
    await auth.updateUser(uid, {
      email,
      password,
      displayName,
      emailVerified: true,
      disabled: false
    });
  } catch (error) {
    if (isUserNotFoundError(error)) {
      await auth.createUser({
        uid,
        email,
        password,
        displayName,
        emailVerified: true,
        disabled: false
      });
      return;
    }

    throw error;
  }
}

export function userProfileDocument(
  email: string,
  nickname: string
): Record<string, unknown> {
  return {
    deviceID: "",
    email,
    gender: "",
    birthdate: "",
    nickname,
    thumbPath: "",
    originalPath: "",
    joinedRooms: [],
    createdAt: FieldValue.serverTimestamp(),
    createdAtISO8601: new Date("2026-05-20T00:00:00.000Z").toISOString()
  };
}

export function markerFields(testRunId: string | undefined): Record<string, unknown> {
  return {
    isTestFixture: true,
    testRunId: testRunId ?? null,
    seededBy: "test-admin-server",
    seededAt: FieldValue.serverTimestamp()
  };
}

export function commentStateDocumentID(commentID: string): string {
  const {brandID, seasonID, postID} = lookbookTestIDs;
  return `${brandID}_${seasonID}_${postID}_${commentID}`;
}

function isUserNotFoundError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "auth/user-not-found"
  );
}
