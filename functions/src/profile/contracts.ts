export const CURRENT_ONBOARDING_VERSION = 1;

export interface CompleteOnboardingInput {
  nickname: string;
  selectedMoodIDs: string[];
  avatarThumbPath: string | null;
  avatarOriginalPath: string | null;
}

export interface PublicProfilePatch {
  nickname?: string;
  avatarThumbPath?: string | null;
  avatarOriginalPath?: string | null;
}

export interface CompleteOnboardingResult {
  userID: string;
  onboardingVersion: number;
}

export interface CheckNicknameAvailabilityResult {
  isAvailable: boolean;
}

export interface UpdatePublicProfileResult {
  userID: string;
  nickname: string;
  avatarThumbPath: string | null;
  avatarOriginalPath: string | null;
}

export interface UpdateStylePreferencesResult {
  userID: string;
  selectedMoodIDs: string[];
}
