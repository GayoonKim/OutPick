/* eslint-disable require-jsdoc */
import {onCall} from "firebase-functions/v2/https";
import {requiredAuthUID} from "../core/callable.js";
import {FUNCTIONS_REGION} from "../core/runtime.js";
import {assertAccountActive} from "../shared/accountStatus.js";
import {
  parseCompleteOnboardingInput,
  parseNicknameAvailabilityInput,
  parsePublicProfilePatch,
  parseStylePreferencesInput,
} from "./policy.js";
import {
  checkNicknameAvailabilityRecord,
  completeOnboardingRecord,
  updatePublicProfileRecord,
  updateStylePreferencesRecord,
} from "./profileTransaction.js";

interface ProfileFunctionDependencies {
  assertActive: typeof assertAccountActive;
  checkNicknameAvailability: typeof checkNicknameAvailabilityRecord;
  completeRecord: typeof completeOnboardingRecord;
  updatePublicRecord: typeof updatePublicProfileRecord;
  updatePreferencesRecord: typeof updateStylePreferencesRecord;
}

const liveDependencies: ProfileFunctionDependencies = {
  assertActive: assertAccountActive,
  checkNicknameAvailability: checkNicknameAvailabilityRecord,
  completeRecord: completeOnboardingRecord,
  updatePublicRecord: updatePublicProfileRecord,
  updatePreferencesRecord: updateStylePreferencesRecord,
};

export async function handleCheckNicknameAvailability(
  authUID: string | undefined,
  data: unknown,
  dependencies = liveDependencies,
) {
  const uid = requiredAuthUID(authUID);
  const nickname = parseNicknameAvailabilityInput(data);
  return dependencies.checkNicknameAvailability(uid, nickname);
}

export async function handleCompleteOnboarding(
  authUID: string | undefined,
  data: unknown,
  dependencies = liveDependencies,
) {
  const uid = requiredAuthUID(authUID);
  const input = parseCompleteOnboardingInput(data, uid);
  return dependencies.completeRecord(uid, input);
}

export async function handleUpdatePublicProfile(
  authUID: string | undefined,
  data: unknown,
  dependencies = liveDependencies,
) {
  const uid = requiredAuthUID(authUID);
  await dependencies.assertActive(uid);
  const patch = parsePublicProfilePatch(data, uid);
  return dependencies.updatePublicRecord(uid, patch);
}

export async function handleUpdateStylePreferences(
  authUID: string | undefined,
  data: unknown,
  dependencies = liveDependencies,
) {
  const uid = requiredAuthUID(authUID);
  await dependencies.assertActive(uid);
  const selectedMoodIDs = parseStylePreferencesInput(data);
  return dependencies.updatePreferencesRecord(uid, selectedMoodIDs);
}

export const completeOnboarding = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleCompleteOnboarding(request.auth?.uid, request.data),
);

export const checkNicknameAvailability = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleCheckNicknameAvailability(request.auth?.uid, request.data),
);

export const updatePublicProfile = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleUpdatePublicProfile(request.auth?.uid, request.data),
);

export const updateStylePreferences = onCall(
  {region: FUNCTIONS_REGION},
  async (request) =>
    handleUpdateStylePreferences(request.auth?.uid, request.data),
);
