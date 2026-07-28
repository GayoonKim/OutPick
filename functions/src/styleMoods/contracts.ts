export const STYLE_MOOD_SCHEMA_VERSION = 1;

export const STYLE_MOOD_DISPLAY_GROUPS = [
  "베이직·포멀",
  "스트릿·트렌드",
  "헤리티지·유틸리티",
  "스포츠·아웃도어",
  "빈티지·서브컬처",
  "로맨틱·익스프레시브",
] as const;

export type StyleMoodDisplayGroup =
  typeof STYLE_MOOD_DISPLAY_GROUPS[number];

export type StyleMoodStatus = "active" | "inactive";
export type StyleMoodTermType = "canonical" | "alias";

export interface StyleMoodValues {
  displayName: string;
  normalizedName: string;
  displayGroup: StyleMoodDisplayGroup;
  aliases: string[];
  sortOrder: number;
  isFeaturedInOnboarding: boolean;
  status: StyleMoodStatus;
}

export interface CreateStyleMoodInput extends StyleMoodValues {
  moodID: string | null;
}

export interface UpdateStyleMoodInput {
  moodID: string;
  displayName?: string;
  displayGroup?: StyleMoodDisplayGroup;
  aliases?: string[];
  sortOrder?: number;
  isFeaturedInOnboarding?: boolean;
  status?: StyleMoodStatus;
}

export interface StyleMoodSeedEntry extends StyleMoodValues {
  moodID: string;
  schemaVersion: number;
}

export interface StyleMoodTerm {
  normalizedTerm: string;
  termType: StyleMoodTermType;
}
