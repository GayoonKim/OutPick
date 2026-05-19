/* eslint-disable require-jsdoc, valid-jsdoc */
import type {Firestore} from "firebase-admin/firestore";
import {FieldValue, Timestamp} from "firebase-admin/firestore";

type ParsedImageCandidate = {
  sourceURL: string;
  alt: string | null;
};

type ImportJobData = {
  brandID?: unknown;
  jobType?: unknown;
  status?: unknown;
  sourceURL?: unknown;
  sourceCandidateID?: unknown;
  sourceTitle?: unknown;
  coverRemoteURL?: unknown;
  sourceSortIndex?: unknown;
  imageCandidates?: unknown;
  targetSeasonID?: unknown;
  contentStatus?: unknown;
};

type SeasonCandidateData = {
  title?: unknown;
  coverImageURL?: unknown;
  sortIndex?: unknown;
};

type MaterializeMetadata = {
  displayTitle: string;
  sourceTitle: string;
  year: number | null;
  term: "ss" | "fw" | null;
  metadataStatus: "unresolved" | "inferred" | "confirmed";
  metadataConfidence: number | null;
  coverRemoteURL: string | null;
  sourceSortIndex: number | null;
};

type JobClaimResult =
  | {
      claimed: true;
      sourceURL: string;
      sourceCandidateID: string | null;
      targetSeasonID: string | null;
    }
  | {
      claimed: false;
      status: "skipped";
      reason: string;
      seasonID?: string;
    };

type SingleMaterializeResult = {
  jobID: string;
  processed: boolean;
  status: "success" | "failed" | "skipped";
  reason?: string;
  seasonID?: string;
  postCount?: number;
  errorMessage?: string;
};

type BatchMaterializeResult = {
  brandID: string;
  requestedJobCount: number;
  processedJobCount: number;
  failedJobCount: number;
  skippedJobCount: number;
  seasonIDs: string[];
  results: SingleMaterializeResult[];
};

const DEFAULT_BATCH_CONCURRENCY = 3;
const MAX_BATCH_CONCURRENCY = 3;

export async function createSeasonContentFromImportJobs(
  db: Firestore,
  brandID: string,
  jobIDs: string[],
  concurrency = DEFAULT_BATCH_CONCURRENCY
): Promise<BatchMaterializeResult> {
  const uniqueJobIDs = Array.from(new Set(jobIDs));
  const safeConcurrency = Math.max(
    1,
    Math.min(MAX_BATCH_CONCURRENCY, Math.floor(concurrency))
  );
  const results: SingleMaterializeResult[] = [];
  let cursor = 0;

  const workers = Array.from(
    {length: Math.min(safeConcurrency, uniqueJobIDs.length)},
    async () => {
      for (;;) {
        const currentIndex = cursor;
        cursor += 1;

        const jobID = uniqueJobIDs[currentIndex];
        if (!jobID) {
          return;
        }

        const result = await materializeParsedSeasonImportJob(
          db,
          brandID,
          jobID
        );
        results[currentIndex] = result;
      }
    }
  );

  await Promise.all(workers);

  return {
    brandID,
    requestedJobCount: uniqueJobIDs.length,
    processedJobCount: results.filter((result) => {
      return result.processed && result.status === "success";
    }).length,
    failedJobCount: results.filter((result) => {
      return result.status === "failed";
    }).length,
    skippedJobCount: results.filter((result) => {
      return result.status === "skipped";
    }).length,
    seasonIDs: results
      .map((result) => result.seasonID)
      .filter((seasonID): seasonID is string => typeof seasonID === "string"),
    results,
  };
}

async function materializeParsedSeasonImportJob(
  db: Firestore,
  brandID: string,
  jobID: string
): Promise<SingleMaterializeResult> {
  const jobRef = db
    .collection("brands")
    .doc(brandID)
    .collection("importJobs")
    .doc(jobID);

  const claim = await db.runTransaction<JobClaimResult>(async (transaction) => {
    const snapshot = await transaction.get(jobRef);
    const data = snapshot.data() as ImportJobData | undefined;

    if (!snapshot.exists) {
      return {
        claimed: false,
        status: "skipped",
        reason: "notFound",
      };
    }

    if (data?.jobType !== "importSeasonFromURL") {
      return {
        claimed: false,
        status: "skipped",
        reason: "invalidJobType",
      };
    }

    const claimedBrandID = stringField(data.brandID, "brandID");
    if (claimedBrandID !== brandID) {
      throw new Error("job 문서의 brandID가 요청 brandID와 다릅니다.");
    }

    const targetSeasonID = optionalStringField(data.targetSeasonID);
    if (targetSeasonID !== null) {
      return {
        claimed: false,
        status: "skipped",
        reason: "alreadyMaterialized",
        seasonID: targetSeasonID,
      };
    }

    if (data.contentStatus === "creating") {
      return {
        claimed: false,
        status: "skipped",
        reason: "alreadyCreating",
      };
    }

    if (data.status !== "parsed" && data.status !== "success") {
      return {
        claimed: false,
        status: "skipped",
        reason: `notParsed:${String(data.status ?? "unknown")}`,
      };
    }

    transaction.update(jobRef, {
      contentStatus: "creating",
      contentErrorMessage: null,
      contentStartedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      claimed: true,
      sourceURL: stringField(data.sourceURL, "sourceURL"),
      sourceCandidateID: optionalStringField(data.sourceCandidateID),
      targetSeasonID: targetSeasonID,
    };
  });

  if (!claim.claimed) {
    return {
      jobID,
      processed: false,
      status: "skipped",
      reason: claim.reason,
      seasonID: claim.seasonID,
    };
  }

  try {
    const freshSnapshot = await jobRef.get();
    const jobData = freshSnapshot.data() as ImportJobData | undefined;
    if (!freshSnapshot.exists || !jobData) {
      throw new Error("import job 문서를 다시 읽지 못했습니다.");
    }

    const imageCandidates = parsedImageCandidates(jobData.imageCandidates);
    if (imageCandidates.length === 0) {
      throw new Error("이미지 후보가 없어 시즌을 만들 수 없습니다.");
    }

    const metadata = await seasonMetadata(
      db,
      brandID,
      claim.sourceURL,
      claim.sourceCandidateID,
      jobData,
      imageCandidates
    );

    const seasonID = deterministicSeasonID(jobID);
    const seasonRef = db
      .collection("brands")
      .doc(brandID)
      .collection("seasons")
      .doc(seasonID);

    const createdPostIDs = imageCandidates.map((_, index) => {
      return deterministicPostID(index);
    });
    const assetTotalCount = imageCandidates.length +
      (metadata.coverRemoteURL !== null ? 1 : 0);

    const now = Date.now();
    const batch = db.batch();
    batch.set(seasonRef, {
      displayTitle: metadata.displayTitle,
      sourceTitle: metadata.sourceTitle,
      year: metadata.year,
      term: metadata.term,
      coverPath: null,
      coverRemoteURL: metadata.coverRemoteURL,
      description: "",
      tagIDs: [],
      tagConceptIDs: [],
      status: "published",
      assetSyncStatus: "pending",
      metadataStatus: metadata.metadataStatus,
      metadataConfidence: metadata.metadataConfidence,
      sourceURL: claim.sourceURL,
      sourceImportJobID: jobID,
      sourceSortIndex: metadata.sourceSortIndex,
      postCount: imageCandidates.length,
      createdAt: Timestamp.fromMillis(now),
      updatedAt: Timestamp.fromMillis(now),
    });

    imageCandidates.forEach((candidate, index) => {
      const postID = createdPostIDs[index];
      const postRef = seasonRef.collection("posts").doc(postID);
      const createdAt = Timestamp.fromMillis(now - index);

      batch.set(postRef, {
        brandID,
        seasonID,
        authorID: null,
        orderIndex: index,
        status: "published",
        assetSyncStatus: "pending",
        sourceImportJobID: jobID,
        media: [
          {
            type: "image",
            remoteURL: candidate.sourceURL,
            thumbPath: null,
            detailPath: null,
            sourcePageURL: claim.sourceURL,
          },
        ],
        caption: normalizedCaption(candidate.alt),
        tagIDs: [],
        metrics: {
          likeCount: 0,
          commentCount: 0,
          replacementCount: 0,
          saveCount: 0,
          viewCount: 0,
        },
        createdAt,
        updatedAt: createdAt,
      });
    });

    batch.update(jobRef, {
      status: "success",
      contentStatus: "created",
      assetSyncStatus: "pending",
      seasonTitle: metadata.displayTitle,
      sourceTitle: metadata.sourceTitle,
      coverRemoteURL: metadata.coverRemoteURL,
      sourceSortIndex: metadata.sourceSortIndex,
      normalizedYear: metadata.year,
      normalizedTerm: metadata.term,
      metadataStatus: metadata.metadataStatus,
      metadataConfidence: metadata.metadataConfidence,
      targetSeasonID: seasonID,
      createdPostIDs,
      createdPostCount: imageCandidates.length,
      assetTotalCount,
      assetCompletedCount: 0,
      assetFailedCount: 0,
      contentCreatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await batch.commit();

    return {
      jobID,
      processed: true,
      status: "success",
      seasonID,
      postCount: imageCandidates.length,
    };
  } catch (error) {
    const message = errorMessage(error);
    await jobRef.update({
      status: "failed",
      contentStatus: "failed",
      contentErrorMessage: message,
      errorMessage: message,
      contentFailedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      jobID,
      processed: true,
      status: "failed",
      errorMessage: message,
    };
  }
}

async function seasonMetadata(
  db: Firestore,
  brandID: string,
  sourceURL: string,
  sourceCandidateID: string | null,
  jobData: ImportJobData,
  imageCandidates: ParsedImageCandidate[]
): Promise<MaterializeMetadata> {
  const candidateData = sourceCandidateID === null ?
    null :
    await loadSeasonCandidate(db, brandID, sourceCandidateID);

  const rawTitle = firstNonEmptyString([
    optionalStringField(jobData.sourceTitle),
    optionalStringField((jobData as Record<string, unknown>).seasonTitle),
    optionalStringField(candidateData?.title),
    derivedTitleFromURL(sourceURL),
  ]) ?? "시즌";

  const normalized = normalizedSeasonMetadata(rawTitle);

  return {
    displayTitle: rawTitle,
    sourceTitle: rawTitle,
    year: normalized.year,
    term: normalized.term,
    metadataStatus: normalized.metadataStatus,
    metadataConfidence: normalized.metadataConfidence,
    coverRemoteURL: firstNonEmptyString([
      optionalStringField(jobData.coverRemoteURL),
      optionalStringField(candidateData?.coverImageURL),
      imageCandidates[0]?.sourceURL ?? null,
    ]),
    sourceSortIndex:
      optionalInteger(jobData.sourceSortIndex) ??
      optionalInteger(candidateData?.sortIndex),
  };
}

async function loadSeasonCandidate(
  db: Firestore,
  brandID: string,
  candidateID: string
): Promise<SeasonCandidateData | null> {
  const snapshot = await db
    .collection("brands")
    .doc(brandID)
    .collection("seasonCandidates")
    .doc(candidateID)
    .get();

  if (!snapshot.exists) {
    return null;
  }
  return snapshot.data() as SeasonCandidateData;
}

function normalizedSeasonMetadata(title: string): {
  year: number | null;
  term: "ss" | "fw" | null;
  metadataStatus: "unresolved" | "inferred" | "confirmed";
  metadataConfidence: number | null;
} {
  const normalized = title.normalize("NFKC").trim();
  const lowercased = normalized.toLowerCase();
  const term = inferSeasonTerm(lowercased);
  const year = inferSeasonYear(lowercased);

  if (year !== null && term !== null) {
    return {
      year,
      term,
      metadataStatus: "inferred",
      metadataConfidence: 0.92,
    };
  }
  if (year !== null || term !== null) {
    return {
      year,
      term,
      metadataStatus: "inferred",
      metadataConfidence: 0.55,
    };
  }
  return {
    year: null,
    term: null,
    metadataStatus: "unresolved",
    metadataConfidence: null,
  };
}

function inferSeasonTerm(value: string): "ss" | "fw" | null {
  if (
    /\bs\/s\b/.test(value) ||
    /\bss\b/.test(value) ||
    /spring\s*[-/ ]\s*summer/.test(value) ||
    /spring\s+summer/.test(value)
  ) {
    return "ss";
  }
  if (
    /\bf\/w\b/.test(value) ||
    /\bfw\b/.test(value) ||
    /\ba\/w\b/.test(value) ||
    /\baw\b/.test(value) ||
    /fall\s*[-/ ]\s*winter/.test(value) ||
    /autumn\s*[-/ ]\s*winter/.test(value) ||
    /fall\s+winter/.test(value) ||
    /autumn\s+winter/.test(value)
  ) {
    return "fw";
  }
  return null;
}

function inferSeasonYear(value: string): number | null {
  const fourDigit = value.match(/\b(20\d{2})\b/);
  if (fourDigit) {
    return Number(fourDigit[1]);
  }

  const twoDigit = value.match(
    /\b(\d{2})\b(?=\s*(?:ss|fw|s\/s|f\/w|aw|a\/w|spring|summer|fall|winter))/
  );
  if (!twoDigit) {
    return null;
  }

  const year = Number(twoDigit[1]);
  if (Number.isNaN(year)) {
    return null;
  }
  return year >= 70 ? 1900 + year : 2000 + year;
}

function derivedTitleFromURL(sourceURL: string): string {
  try {
    const url = new URL(sourceURL);
    const fileName = url.pathname.split("/").filter(Boolean).pop() ?? "";
    const normalized = fileName
      .replace(/\.(html?|php)$/i, "")
      .replace(/[-_]+/g, " ")
      .trim();
    return normalized.length > 0 ? normalized : "시즌";
  } catch {
    return "시즌";
  }
}

function parsedImageCandidates(value: unknown): ParsedImageCandidate[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => {
      if (item === null || typeof item !== "object" || Array.isArray(item)) {
        return null;
      }

      const sourceURL = optionalStringField(
        (item as Record<string, unknown>).sourceURL
      );
      if (sourceURL === null) {
        return null;
      }

      return {
        sourceURL,
        alt: optionalStringField((item as Record<string, unknown>).alt),
      };
    })
    .filter((item): item is ParsedImageCandidate => item !== null);
}

function deterministicSeasonID(jobID: string): string {
  return `import_${jobID}`;
}

function deterministicPostID(index: number): string {
  return `post_${String(index).padStart(4, "0")}`;
}

function normalizedCaption(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function stringField(value: unknown, fieldName: string): string {
  if (typeof value !== "string") {
    throw new Error(`${fieldName} 값이 필요합니다.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new Error(`${fieldName} 값이 비어 있습니다.`);
  }
  return trimmed;
}

function optionalStringField(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function optionalInteger(value: unknown): number | null {
  if (!Number.isInteger(value)) {
    return null;
  }
  return Number(value);
}

function firstNonEmptyString(values: Array<string | null>): string | null {
  return values.find((value) => {
    return typeof value === "string" && value.trim().length > 0;
  }) ?? null;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return String(error);
}
