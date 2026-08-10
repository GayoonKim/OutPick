/* eslint-disable require-jsdoc */

export type PlatformAdminProvider = "google" | "kakao";
export type PlatformAdminOperation = "audit" | "grant" | "revoke";

export const productionPlatformAdminConfirmations = {
  grant: "GRANT_SINGLE_PLATFORM_ADMIN_TO_OUTPICK_664AE",
  revoke: "REVOKE_SINGLE_PLATFORM_ADMIN_FROM_OUTPICK_664AE",
} as const;

export function platformAdminProvider(
  uid: string,
  providerIDs: readonly string[],
): PlatformAdminProvider | null {
  const google = providerIDs.includes("google.com");
  const kakao = uid.startsWith("kakao:");
  if (google === kakao) return null;
  return google ? "google" : "kakao";
}

export function assertPlatformAdminOperationGate(input: {
  projectID: string;
  operation: PlatformAdminOperation;
  apply: boolean;
  confirmation: string | null;
  expectedAuthCount: number | null;
  actualAuthCount: number;
  expectedProviderCount: number | null;
  actualProviderCount: number;
}): void {
  const allowedProject = input.projectID === "outpick-test" ||
    input.projectID === "outpick-664ae";
  if (!allowedProject) {
    throw new Error("허용되지 않은 Firebase project입니다.");
  }
  if (!input.apply) return;
  if (input.operation === "audit") {
    throw new Error("audit 작업에는 --apply를 사용할 수 없습니다.");
  }
  if (input.actualProviderCount !== 1) {
    throw new Error("선택 provider의 Auth 계정이 정확히 1명이 아닙니다.");
  }
  if (input.projectID !== "outpick-664ae") return;
  if (input.expectedAuthCount === null ||
    input.expectedAuthCount !== input.actualAuthCount) {
    throw new Error("Production Auth 예상 건수가 일치하지 않습니다.");
  }
  if (input.expectedProviderCount === null ||
    input.expectedProviderCount !== input.actualProviderCount) {
    throw new Error("Production provider 예상 건수가 일치하지 않습니다.");
  }
  const expected = productionPlatformAdminConfirmations[input.operation];
  if (input.confirmation !== expected) {
    throw new Error("Production 확인 문자열이 일치하지 않습니다.");
  }
}
