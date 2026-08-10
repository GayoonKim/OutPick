/* eslint-disable require-jsdoc, max-len */
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../core/firebase.js";
import {
  MODERATION_HMAC_KEY_VERSION,
  MODERATION_ACCOUNT_SCHEMA_VERSION,
  MODERATION_SCHEMA_VERSION,
  AccountStatus,
  ModerationHmacKey,
  ModerationState,
  ModerationStatus,
  ProviderIdentity,
  moderationCapabilities,
} from "./contracts.js";
import {moderationAliasID} from "./identity.js";

function timestampDate(value: unknown): Date | null {
  return value instanceof Timestamp ? value.toDate() : null;
}

function storedStatus(value: unknown): ModerationStatus {
  if (value === "active" || value === "restricted" || value === "suspended") {
    return value;
  }
  throw new HttpsError("failed-precondition", "제재 상태 문서가 올바르지 않습니다.");
}

function accountStatus(value: unknown): AccountStatus {
  if (value === "active" || value === "deletionPending") return value;
  throw new HttpsError("failed-precondition", "계정 상태 문서가 올바르지 않습니다.");
}

export function effectiveModerationState(
  data: FirebaseFirestore.DocumentData,
  now: Date,
): ModerationState {
  const stored = storedStatus(data.moderationStatus);
  const restrictedUntil = timestampDate(data.restrictedUntil);
  const expired = stored === "restricted" &&
    restrictedUntil !== null && restrictedUntil.getTime() <= now.getTime();
  return {
    moderationStatus: expired ? "active" : stored,
    restrictedUntil: expired ? null : restrictedUntil,
    stateVersion: typeof data.stateVersion === "number" && data.stateVersion >= 1 ?
      data.stateVersion : 1,
    noticeReasonCode: !expired && typeof data.noticeReasonCode === "string" ?
      data.noticeReasonCode : null,
  };
}

export async function bindModerationPrincipal(
  uid: string,
  identity: ProviderIdentity,
  currentKey: string | ModerationHmacKey,
  now = new Date(),
  previousKeys: readonly ModerationHmacKey[] = [],
  database: Firestore = db,
): Promise<ModerationState> {
  const normalizedCurrentKey = typeof currentKey === "string" ? {
    version: MODERATION_HMAC_KEY_VERSION,
    secret: currentKey,
  } : currentKey;
  const lookupKeys = [normalizedCurrentKey, ...previousKeys]
    .filter((key, index, keys) =>
      keys.findIndex((candidate) => candidate.version === key.version) === index
    );
  const aliasIDs = lookupKeys.map((key) =>
    moderationAliasID(identity, key.secret, key.version)
  );
  const accountRef = database.collection("moderationAccounts").doc(uid);
  const userRef = database.collection("users").doc(uid);
  const aliasRefs = aliasIDs.map((aliasID) =>
    database.collection("moderationPrincipalAliases").doc(aliasID)
  );
  const currentAliasRef = aliasRefs[0];
  const newPrincipalRef = database.collection("moderationPrincipals").doc();
  const nowTimestamp = Timestamp.fromDate(now);

  return database.runTransaction(async (transaction) => {
    const [accountSnapshot, userSnapshot, ...aliasSnapshots] = await transaction.getAll(
      accountRef,
      userRef,
      ...aliasRefs,
    );
    const projectedAccountStatus = userSnapshot.exists ?
      accountStatus(userSnapshot.get("accountStatus")) : "active";
    const accountPrincipalID = accountSnapshot.exists ?
      accountSnapshot.get("moderationPrincipalID") : null;
    const aliasPrincipalIDs = aliasSnapshots
      .filter((snapshot) => snapshot.exists)
      .map((snapshot) => snapshot.get("moderationPrincipalID"))
      .filter((value): value is string => typeof value === "string");
    const knownPrincipalIDs = [accountPrincipalID, ...aliasPrincipalIDs]
      .filter((value): value is string => typeof value === "string");
    if (new Set(knownPrincipalIDs).size > 1) {
      throw new HttpsError(
        "failed-precondition",
        "로그인 식별자와 현재 계정의 제재 주체가 일치하지 않습니다.",
      );
    }
    const principalID = knownPrincipalIDs[0] ?? newPrincipalRef.id;
    if (typeof principalID !== "string" || principalID.length === 0) {
      throw new HttpsError("failed-precondition", "제재 주체 문서가 올바르지 않습니다.");
    }
    const principalRef = database.collection("moderationPrincipals").doc(principalID);
    const principalSnapshot = await transaction.get(principalRef);
    const initialData = {
      schemaVersion: MODERATION_SCHEMA_VERSION,
      moderationStatus: "active",
      restrictedUntil: null,
      stateVersion: 1,
      noticeReasonCode: null,
      createdAt: nowTimestamp,
      updatedAt: nowTimestamp,
      expiresAt: null,
    };
    const sourceData = principalSnapshot.exists ? principalSnapshot.data() : initialData;
    if (!sourceData) {
      throw new HttpsError("failed-precondition", "제재 주체 상태를 읽을 수 없습니다.");
    }
    const state = effectiveModerationState(sourceData, now);
    const normalizedVersion = state.moderationStatus !== sourceData.moderationStatus ?
      state.stateVersion + 1 : state.stateVersion;
    const normalizedState = {...state, stateVersion: normalizedVersion};

    transaction.set(principalRef, {
      ...initialData,
      ...sourceData,
      moderationStatus: normalizedState.moderationStatus,
      restrictedUntil: normalizedState.restrictedUntil ?
        Timestamp.fromDate(normalizedState.restrictedUntil) : null,
      stateVersion: normalizedState.stateVersion,
      updatedAt: nowTimestamp,
    }, {merge: true});
    const currentAliasSnapshot = aliasSnapshots[0];
    transaction.set(currentAliasRef, {
      schemaVersion: MODERATION_SCHEMA_VERSION,
      moderationPrincipalID: principalID,
      provider: identity.provider,
      keyVersion: normalizedCurrentKey.version,
      createdAt: currentAliasSnapshot.exists ?
        currentAliasSnapshot.get("createdAt") : nowTimestamp,
      expiresAt: null,
    });
    transaction.set(accountRef, {
      schemaVersion: MODERATION_ACCOUNT_SCHEMA_VERSION,
      accountStatus: projectedAccountStatus,
      moderationPrincipalID: principalID,
      moderationStatus: normalizedState.moderationStatus,
      restrictedUntil: normalizedState.restrictedUntil ?
        Timestamp.fromDate(normalizedState.restrictedUntil) : null,
      stateVersion: normalizedState.stateVersion,
      noticeReasonCode: normalizedState.noticeReasonCode,
      updatedAt: nowTimestamp,
    });
    return normalizedState;
  });
}

export function allowedCapabilities(status: ModerationStatus): readonly string[] {
  return moderationCapabilities[status];
}
