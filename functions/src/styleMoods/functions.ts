/* eslint-disable require-jsdoc */
import {onCall} from "firebase-functions/v2/https";
import {recordData, requiredAuthUID} from "../core/callable.js";
import {FUNCTIONS_REGION} from "../core/runtime.js";
import {assertBrandCreationAccess} from "../shared/brandAuthorization.js";
import {
  parseCreateStyleMoodInput,
  parseUpdateStyleMoodInput,
} from "./policy.js";
import {
  createStyleMoodRecord,
  updateStyleMoodRecord,
} from "./repository.js";

interface StyleMoodFunctionDependencies {
  assertTotalAdmin: (uid: string) => Promise<void>;
  createRecord: typeof createStyleMoodRecord;
  updateRecord: typeof updateStyleMoodRecord;
  now: () => number;
}

const liveDependencies: StyleMoodFunctionDependencies = {
  assertTotalAdmin: assertBrandCreationAccess,
  createRecord: createStyleMoodRecord,
  updateRecord: updateStyleMoodRecord,
  now: Date.now,
};

export async function handleCreateStyleMood(
  authUID: string | undefined,
  rawData: unknown,
  dependencies = liveDependencies
): Promise<{moodID: string}> {
  const uid = requiredAuthUID(authUID);
  const data = recordData(rawData);
  await dependencies.assertTotalAdmin(uid);
  const input = parseCreateStyleMoodInput(data, dependencies.now());
  const moodID = await dependencies.createRecord(input);
  return {moodID};
}

export async function handleUpdateStyleMood(
  authUID: string | undefined,
  rawData: unknown,
  dependencies = liveDependencies
): Promise<{moodID: string}> {
  const uid = requiredAuthUID(authUID);
  const data = recordData(rawData);
  await dependencies.assertTotalAdmin(uid);
  const input = parseUpdateStyleMoodInput(data);
  await dependencies.updateRecord(input);
  return {moodID: input.moodID};
}

export const createStyleMood = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleCreateStyleMood(request.auth?.uid, request.data)
);

export const updateStyleMood = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleUpdateStyleMood(request.auth?.uid, request.data)
);
