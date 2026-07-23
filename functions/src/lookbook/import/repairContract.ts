/* eslint-disable require-jsdoc */
export type RepairApplyEntry = {
  postID: string;
  sourceURL: string;
  proposedIndex: number;
};

export type RepairAddEntry = RepairApplyEntry & {
  candidateKey: string;
  alt: string | null;
  contentHash: string | null;
};

export type SeasonRepairPlan = {
  keep: RepairApplyEntry[];
  reorder: RepairApplyEntry[];
  add: RepairAddEntry[];
  removeCandidates: RepairApplyEntry[];
  orderedPostIDs: string[];
  allPostIDs: string[];
  resultingPostCount: number;
};

export function seasonRepairPlan(
  value: Record<string, unknown>
): SeasonRepairPlan {
  const keep = repairApplyEntries(value.keep, "keep");
  const reorder = repairApplyEntries(value.reorder, "reorder");
  const add = repairAddEntries(value.add);
  const removeCandidates = repairApplyEntries(
    value.removeCandidates,
    "removeCandidates"
  );
  const orderedPostIDs = stringIDs(value.orderedPostIDs, "orderedPostIDs");
  const allPostIDs = stringIDs(value.allPostIDs, "allPostIDs");
  const resultingPostCount = requiredNonNegativeInteger(
    value.resultingPostCount,
    "resultingPostCount"
  );
  if (new Set(allPostIDs).size !== allPostIDs.length) {
    throw new Error("allPostIDs에 중복이 있습니다.");
  }
  if (resultingPostCount !== allPostIDs.length) {
    throw new Error("resultingPostCount가 post ID 개수와 다릅니다.");
  }
  return {
    keep,
    reorder,
    add,
    removeCandidates,
    orderedPostIDs,
    allPostIDs,
    resultingPostCount,
  };
}

export function repairRequestDisposition(input: {
  jobStatus: unknown;
  repairStatus: unknown;
  repairTargetSeasonID: unknown;
  requestedSeasonID: string;
}): "start" | "duplicate" {
  if (
    input.repairTargetSeasonID === input.requestedSeasonID &&
    (
      (
        input.repairStatus === "analyzing" &&
        (
          input.jobStatus === "queued" ||
          input.jobStatus === "processing"
        )
      ) ||
      (
        input.repairStatus === "previewReady" &&
        input.jobStatus === "awaitingReview"
      )
    )
  ) {
    return "duplicate";
  }
  if (
    input.jobStatus === "queued" ||
    input.jobStatus === "processing" ||
    input.jobStatus === "awaitingReview"
  ) {
    throw new Error("현재 진행 중인 작업이 있어 시즌 보수를 시작할 수 없습니다.");
  }
  return "start";
}

function repairApplyEntries(
  value: unknown,
  fieldName: string
): RepairApplyEntry[] {
  return records(value, fieldName).map((item) => ({
    postID: documentID(item.postID, `${fieldName}.postID`),
    sourceURL: httpURL(item.sourceURL, `${fieldName}.sourceURL`),
    proposedIndex: requiredNonNegativeInteger(
      item.proposedIndex,
      `${fieldName}.proposedIndex`
    ),
  }));
}

function repairAddEntries(value: unknown): RepairAddEntry[] {
  return records(value, "add").map((item) => ({
    postID: documentID(item.postID, "add.postID"),
    candidateKey: documentID(item.candidateKey, "add.candidateKey"),
    sourceURL: httpURL(item.sourceURL, "add.sourceURL"),
    alt: optionalString(item.alt),
    contentHash: optionalHash(item.contentHash),
    proposedIndex: requiredNonNegativeInteger(
      item.proposedIndex,
      "add.proposedIndex"
    ),
  }));
}

function records(
  value: unknown,
  fieldName: string
): Array<Record<string, unknown>> {
  if (!Array.isArray(value) || value.length > 240) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return value.map((item) => {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
    }
    return item as Record<string, unknown>;
  });
}

function stringIDs(value: unknown, fieldName: string): string[] {
  if (!Array.isArray(value) || value.length > 480) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return value.map((item) => documentID(item, fieldName));
}

function documentID(value: unknown, fieldName: string): string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 128 ||
    value.includes("/")
  ) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return value;
}

function httpURL(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || value.length > 2048) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  const url = new URL(value);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return url.toString();
}

function requiredNonNegativeInteger(
  value: unknown,
  fieldName: string
): number {
  if (!Number.isInteger(value) || Number(value) < 0) {
    throw new Error(`${fieldName} 값이 올바르지 않습니다.`);
  }
  return Number(value);
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ?
    value.trim().slice(0, 500) :
    null;
}

function optionalHash(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) {
    throw new Error("contentHash 값이 올바르지 않습니다.");
  }
  return value;
}
