/* eslint-disable require-jsdoc */
import {createHash} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {
  CreateStyleMoodInput,
  STYLE_MOOD_DISPLAY_GROUPS,
  STYLE_MOOD_SCHEMA_VERSION,
  StyleMoodDisplayGroup,
  StyleMoodSeedEntry,
  StyleMoodStatus,
  StyleMoodTerm,
  StyleMoodValues,
  UpdateStyleMoodInput,
} from "./contracts.js";

const MOOD_ID_PATTERN = /^[a-z0-9]+(?:_[a-z0-9]+)*$/;
const MAX_DISPLAY_NAME_LENGTH = 40;
const MAX_ALIAS_COUNT = 20;
const MAX_ALIAS_LENGTH = 60;
const MAX_SORT_ORDER = Number.MAX_SAFE_INTEGER;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export function canonicalStyleMoodTerm(rawValue: string): string {
  return rawValue.normalize("NFKC").trim().replace(/\s+/g, " ");
}

export function normalizedStyleMoodTerm(rawValue: string): string {
  return canonicalStyleMoodTerm(rawValue).toLowerCase();
}

export function styleMoodTermIndexID(normalizedTerm: string): string {
  return createHash("sha256").update(normalizedTerm).digest("hex");
}

export function requiredStyleMoodID(rawValue: unknown): string {
  if (typeof rawValue !== "string") {
    return invalid("moodID 값이 필요합니다.");
  }
  const moodID = rawValue.trim();
  if (
    moodID.length === 0 ||
    moodID.length > 64 ||
    !MOOD_ID_PATTERN.test(moodID)
  ) {
    return invalid("moodID 값은 lower_snake_case 형식이어야 합니다.");
  }
  return moodID;
}

function requiredDisplayName(rawValue: unknown): string {
  if (typeof rawValue !== "string") {
    return invalid("displayName 값이 필요합니다.");
  }
  const displayName = canonicalStyleMoodTerm(rawValue);
  if (
    displayName.length === 0 ||
    displayName.length > MAX_DISPLAY_NAME_LENGTH
  ) {
    return invalid("displayName 값이 올바르지 않습니다.");
  }
  return displayName;
}

function requiredDisplayGroup(rawValue: unknown): StyleMoodDisplayGroup {
  if (
    typeof rawValue !== "string" ||
    !STYLE_MOOD_DISPLAY_GROUPS.some((group) => group === rawValue)
  ) {
    return invalid("displayGroup 값이 올바르지 않습니다.");
  }
  return rawValue as StyleMoodDisplayGroup;
}

function requiredBoolean(rawValue: unknown, fieldName: string): boolean {
  if (typeof rawValue !== "boolean") {
    return invalid(`${fieldName} 값이 필요합니다.`);
  }
  return rawValue;
}

function requiredSortOrder(rawValue: unknown): number {
  if (
    typeof rawValue !== "number" ||
    !Number.isSafeInteger(rawValue) ||
    rawValue < 0 ||
    rawValue > MAX_SORT_ORDER
  ) {
    return invalid("sortOrder 값이 올바르지 않습니다.");
  }
  return rawValue;
}

function requiredStatus(rawValue: unknown): StyleMoodStatus {
  if (rawValue !== "active" && rawValue !== "inactive") {
    return invalid("status 값이 올바르지 않습니다.");
  }
  return rawValue;
}

export function canonicalStyleMoodAliases(
  rawValue: unknown,
  normalizedName: string
): string[] {
  if (!Array.isArray(rawValue) || rawValue.length > MAX_ALIAS_COUNT) {
    return invalid(`aliases 값은 최대 ${MAX_ALIAS_COUNT}개여야 합니다.`);
  }

  const aliases: string[] = [];
  const normalizedAliases = new Set<string>();
  for (const rawAlias of rawValue) {
    if (typeof rawAlias !== "string") {
      return invalid("aliases 값이 올바르지 않습니다.");
    }
    const alias = canonicalStyleMoodTerm(rawAlias);
    if (alias.length === 0 || alias.length > MAX_ALIAS_LENGTH) {
      return invalid("alias 값이 올바르지 않습니다.");
    }
    const normalizedAlias = normalizedStyleMoodTerm(alias);
    if (
      normalizedAlias === normalizedName ||
      normalizedAliases.has(normalizedAlias)
    ) {
      return invalid("displayName 또는 aliases 안에 중복 용어가 있습니다.");
    }
    normalizedAliases.add(normalizedAlias);
    aliases.push(alias);
  }
  return aliases;
}

export function styleMoodTerms(values: Pick<
  StyleMoodValues,
  "normalizedName" | "aliases"
>): StyleMoodTerm[] {
  return [
    {normalizedTerm: values.normalizedName, termType: "canonical"},
    ...values.aliases.map((alias) => ({
      normalizedTerm: normalizedStyleMoodTerm(alias),
      termType: "alias" as const,
    })),
  ];
}

function optionalField(
  data: Record<string, unknown>,
  key: string
): boolean {
  return Object.prototype.hasOwnProperty.call(data, key);
}

export function parseCreateStyleMoodInput(
  data: Record<string, unknown>,
  defaultSortOrder: number
): CreateStyleMoodInput {
  const displayName = requiredDisplayName(data.displayName);
  const normalizedName = normalizedStyleMoodTerm(displayName);
  const rawMoodID = data.moodID;
  const moodID = rawMoodID === undefined || rawMoodID === null ?
    null :
    requiredStyleMoodID(rawMoodID);

  return {
    moodID,
    displayName,
    normalizedName,
    displayGroup: requiredDisplayGroup(data.displayGroup),
    aliases: canonicalStyleMoodAliases(data.aliases ?? [], normalizedName),
    sortOrder: optionalField(data, "sortOrder") ?
      requiredSortOrder(data.sortOrder) :
      requiredSortOrder(defaultSortOrder),
    isFeaturedInOnboarding: optionalField(
      data,
      "isFeaturedInOnboarding"
    ) ?
      requiredBoolean(
        data.isFeaturedInOnboarding,
        "isFeaturedInOnboarding"
      ) :
      false,
    status: "active",
  };
}

export function parseUpdateStyleMoodInput(
  data: Record<string, unknown>
): UpdateStyleMoodInput {
  const input: UpdateStyleMoodInput = {
    moodID: requiredStyleMoodID(data.moodID),
  };

  if (optionalField(data, "displayName")) {
    input.displayName = requiredDisplayName(data.displayName);
  }
  if (optionalField(data, "displayGroup")) {
    input.displayGroup = requiredDisplayGroup(data.displayGroup);
  }
  if (optionalField(data, "aliases")) {
    const normalizedName = input.displayName === undefined ?
      "" :
      normalizedStyleMoodTerm(input.displayName);
    input.aliases = canonicalStyleMoodAliases(
      data.aliases,
      normalizedName
    );
  }
  if (optionalField(data, "sortOrder")) {
    input.sortOrder = requiredSortOrder(data.sortOrder);
  }
  if (optionalField(data, "isFeaturedInOnboarding")) {
    input.isFeaturedInOnboarding = requiredBoolean(
      data.isFeaturedInOnboarding,
      "isFeaturedInOnboarding"
    );
  }
  if (optionalField(data, "status")) {
    input.status = requiredStatus(data.status);
  }

  if (Object.keys(input).length === 1) {
    return invalid("수정할 무드 필드가 없습니다.");
  }
  return input;
}

export function resolveStyleMoodUpdate(
  current: StyleMoodValues,
  input: UpdateStyleMoodInput
): StyleMoodValues {
  const displayName = input.displayName ?? current.displayName;
  const normalizedName = normalizedStyleMoodTerm(displayName);
  const aliases = canonicalStyleMoodAliases(
    input.aliases ?? current.aliases,
    normalizedName
  );

  return {
    displayName,
    normalizedName,
    displayGroup: input.displayGroup ?? current.displayGroup,
    aliases,
    sortOrder: input.sortOrder ?? current.sortOrder,
    isFeaturedInOnboarding:
      input.isFeaturedInOnboarding ?? current.isFeaturedInOnboarding,
    status: input.status ?? current.status,
  };
}

export function validateStyleMoodSeedEntries(
  rawEntries: unknown
): StyleMoodSeedEntry[] {
  if (!Array.isArray(rawEntries) || rawEntries.length === 0) {
    return invalid("style mood seed는 비어 있을 수 없습니다.");
  }

  const moodIDs = new Set<string>();
  const termOwners = new Map<string, string>();
  const sortOrders = new Set<number>();

  return rawEntries.map((rawEntry) => {
    if (
      rawEntry === null ||
      typeof rawEntry !== "object" ||
      Array.isArray(rawEntry)
    ) {
      return invalid("style mood seed 항목이 올바르지 않습니다.");
    }
    const data = rawEntry as Record<string, unknown>;
    if (data.schemaVersion !== STYLE_MOOD_SCHEMA_VERSION) {
      return invalid("지원하지 않는 style mood schemaVersion입니다.");
    }
    const moodID = requiredStyleMoodID(data.moodID);
    if (moodIDs.has(moodID)) {
      return invalid(`중복 moodID입니다: ${moodID}`);
    }
    moodIDs.add(moodID);

    const displayName = requiredDisplayName(data.displayName);
    const normalizedName = normalizedStyleMoodTerm(displayName);
    const aliases = canonicalStyleMoodAliases(
      data.aliases ?? [],
      normalizedName
    );
    const sortOrder = requiredSortOrder(data.sortOrder);
    if (sortOrders.has(sortOrder)) {
      return invalid(`중복 sortOrder입니다: ${sortOrder}`);
    }
    sortOrders.add(sortOrder);

    const entry: StyleMoodSeedEntry = {
      moodID,
      schemaVersion: STYLE_MOOD_SCHEMA_VERSION,
      displayName,
      normalizedName,
      displayGroup: requiredDisplayGroup(data.displayGroup),
      aliases,
      sortOrder,
      isFeaturedInOnboarding: requiredBoolean(
        data.isFeaturedInOnboarding,
        "isFeaturedInOnboarding"
      ),
      status: requiredStatus(data.status),
    };

    for (const term of styleMoodTerms(entry)) {
      const existingOwner = termOwners.get(term.normalizedTerm);
      if (existingOwner !== undefined) {
        return invalid(
          `seed 용어가 충돌합니다: ${term.normalizedTerm} ` +
          `(${existingOwner}, ${moodID})`
        );
      }
      termOwners.set(term.normalizedTerm, moodID);
    }
    return entry;
  });
}
