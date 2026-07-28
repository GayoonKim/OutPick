/* eslint-disable require-jsdoc, max-len, no-control-regex */
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {
  CompleteOnboardingInput,
  PublicProfilePatch,
} from "./contracts.js";

const MIN_NICKNAME_LENGTH = 2;
const MAX_NICKNAME_LENGTH = 20;
const MAX_SELECTED_MOOD_COUNT = 5;
const DISALLOWED_NICKNAME_PATTERN = /[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060-\u206F]/u;

type RecordValue = Record<string, unknown>;

function requireRecord(value: unknown): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "요청 형식이 올바르지 않습니다.");
  }
  return value as RecordValue;
}

function assertOnlyKeys(record: RecordValue, allowedKeys: string[]): void {
  const allowed = new Set(allowedKeys);
  if (Object.keys(record).some((key) => !allowed.has(key))) {
    throw new HttpsError("invalid-argument", "지원하지 않는 필드가 포함되어 있습니다.");
  }
}

export function normalizeNicknameDisplay(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "닉네임을 입력해 주세요.");
  }

  const normalized = value.normalize("NFKC").trim().replace(/\s+/gu, " ");
  const length = Array.from(normalized).length;
  if (length < MIN_NICKNAME_LENGTH || length > MAX_NICKNAME_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `닉네임은 ${MIN_NICKNAME_LENGTH}~${MAX_NICKNAME_LENGTH}자로 입력해 주세요.`,
    );
  }
  if (DISALLOWED_NICKNAME_PATTERN.test(normalized)) {
    throw new HttpsError("invalid-argument", "닉네임에 사용할 수 없는 문자가 포함되어 있습니다.");
  }
  return normalized;
}

export function normalizeNicknameKey(nickname: string): string {
  return nickname.normalize("NFKC").toLocaleLowerCase("ko-KR");
}

export function nicknameIndexID(nickname: string): string {
  return createHash("sha256").update(normalizeNicknameKey(nickname), "utf8").digest("hex");
}

export function parseSelectedMoodIDs(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "관심 무드를 선택해 주세요.");
  }
  if (value.length < 1 || value.length > MAX_SELECTED_MOOD_COUNT) {
    throw new HttpsError(
      "invalid-argument",
      `관심 무드는 1~${MAX_SELECTED_MOOD_COUNT}개 선택해 주세요.`,
    );
  }

  const moodIDs = value.map((item) => {
    if (
      typeof item !== "string" ||
      item.length === 0 ||
      item.length > 128 ||
      item.includes("/")
    ) {
      throw new HttpsError("invalid-argument", "유효하지 않은 무드 ID가 포함되어 있습니다.");
    }
    return item;
  });

  if (new Set(moodIDs).size !== moodIDs.length) {
    throw new HttpsError("invalid-argument", "같은 관심 무드를 중복 선택할 수 없습니다.");
  }
  return moodIDs;
}

function parseAvatarPath(
  value: unknown,
  uid: string,
  variant: "thumb" | "original",
): string | null {
  if (value === null) {
    return null;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "프로필 이미지 경로가 올바르지 않습니다.");
  }

  const prefix = `profileImage/${uid}/${variant}/`;
  const fileName = value.slice(prefix.length);
  if (
    !value.startsWith(prefix) ||
    fileName.length === 0 ||
    fileName.length > 255 ||
    fileName.includes("/") ||
    fileName === "." ||
    fileName === ".."
  ) {
    throw new HttpsError("invalid-argument", "프로필 이미지 경로가 올바르지 않습니다.");
  }
  return value;
}

export function parseCompleteOnboardingInput(
  data: unknown,
  uid: string,
): CompleteOnboardingInput {
  const record = requireRecord(data);
  assertOnlyKeys(record, [
    "nickname",
    "selectedMoodIDs",
    "avatarThumbPath",
    "avatarOriginalPath",
  ]);

  return {
    nickname: normalizeNicknameDisplay(record.nickname),
    selectedMoodIDs: parseSelectedMoodIDs(record.selectedMoodIDs),
    avatarThumbPath: record.avatarThumbPath === undefined ?
      null :
      parseAvatarPath(record.avatarThumbPath, uid, "thumb"),
    avatarOriginalPath: record.avatarOriginalPath === undefined ?
      null :
      parseAvatarPath(record.avatarOriginalPath, uid, "original"),
  };
}

export function parseNicknameAvailabilityInput(data: unknown): string {
  const record = requireRecord(data);
  assertOnlyKeys(record, ["nickname"]);
  return normalizeNicknameDisplay(record.nickname);
}

export function parsePublicProfilePatch(
  data: unknown,
  uid: string,
): PublicProfilePatch {
  const record = requireRecord(data);
  assertOnlyKeys(record, ["nickname", "avatarThumbPath", "avatarOriginalPath"]);
  if (Object.keys(record).length === 0) {
    throw new HttpsError("invalid-argument", "변경할 프로필 정보를 입력해 주세요.");
  }

  const patch: PublicProfilePatch = {};
  if (Object.prototype.hasOwnProperty.call(record, "nickname")) {
    patch.nickname = normalizeNicknameDisplay(record.nickname);
  }
  if (Object.prototype.hasOwnProperty.call(record, "avatarThumbPath")) {
    patch.avatarThumbPath = parseAvatarPath(record.avatarThumbPath, uid, "thumb");
  }
  if (Object.prototype.hasOwnProperty.call(record, "avatarOriginalPath")) {
    patch.avatarOriginalPath = parseAvatarPath(record.avatarOriginalPath, uid, "original");
  }
  return patch;
}

export function parseStylePreferencesInput(data: unknown): string[] {
  const record = requireRecord(data);
  assertOnlyKeys(record, ["selectedMoodIDs"]);
  return parseSelectedMoodIDs(record.selectedMoodIDs);
}
