import {createHash} from "node:crypto";

import {canonicalCandidateURL} from "./dedupe.js";

export type ReconcileExistingPost = {
  postID: string;
  sourceURL: string;
  contentHash: string | null;
  sourceSortIndex: number;
};

export type ReconcileCandidate = {
  candidateKey: string;
  sourceURL: string;
  alt: string | null;
  contentHash: string | null;
};

export type ReconcileKeepEntry = {
  kind: "keep";
  postID: string;
  candidateKey: string;
  sourceURL: string;
  previousIndex: number;
  proposedIndex: number;
  matchedBy: "canonicalURL" | "contentHash";
};

export type ReconcileReorderEntry = Omit<ReconcileKeepEntry, "kind"> & {
  kind: "reorder";
};

export type ReconcileAddEntry = {
  kind: "add";
  postID: string;
  candidateKey: string;
  sourceURL: string;
  alt: string | null;
  contentHash: string | null;
  proposedIndex: number;
};

export type ReconcileRemoveCandidateEntry = {
  kind: "removeCandidate";
  postID: string;
  sourceURL: string;
  previousIndex: number;
  proposedIndex: number;
};

export type SeasonReconcilePreview = {
  keep: ReconcileKeepEntry[];
  add: ReconcileAddEntry[];
  reorder: ReconcileReorderEntry[];
  removeCandidates: ReconcileRemoveCandidateEntry[];
  orderedPostIDs: string[];
  allPostIDs: string[];
  resultingPostCount: number;
  snapshotHash: string;
};

export function seasonRepairPreviewDisposition(
  preview: Pick<
    SeasonReconcilePreview,
    "add" | "reorder" | "removeCandidates"
  >,
): "noChanges" | "reviewRequired" {
  return preview.add.length === 0 &&
    preview.reorder.length === 0 &&
    preview.removeCandidates.length === 0 ?
    "noChanges" :
    "reviewRequired";
}

export function makeSeasonReconcilePreview(input: {
  existingPosts: ReconcileExistingPost[];
  candidates: ReconcileCandidate[];
}): SeasonReconcilePreview {
  const unmatched = new Map(
    input.existingPosts.map((post) => [post.postID, post]),
  );
  const keep: ReconcileKeepEntry[] = [];
  const reorder: ReconcileReorderEntry[] = [];
  const add: ReconcileAddEntry[] = [];
  const orderedPostIDs: string[] = [];

  input.candidates.forEach((candidate, proposedIndex) => {
    const match = findMatch(candidate, Array.from(unmatched.values()));
    if (match === null) {
      const entry: ReconcileAddEntry = {
        kind: "add",
        postID: deterministicRepairPostID(candidate),
        candidateKey: candidate.candidateKey,
        sourceURL: candidate.sourceURL,
        alt: candidate.alt,
        contentHash: candidate.contentHash,
        proposedIndex,
      };
      add.push(entry);
      orderedPostIDs.push(entry.postID);
      return;
    }
    unmatched.delete(match.post.postID);
    const shared = {
      postID: match.post.postID,
      candidateKey: candidate.candidateKey,
      sourceURL: candidate.sourceURL,
      previousIndex: match.post.sourceSortIndex,
      proposedIndex,
      matchedBy: match.matchedBy,
    };
    if (match.post.sourceSortIndex === proposedIndex) {
      keep.push({kind: "keep", ...shared});
    } else {
      reorder.push({kind: "reorder", ...shared});
    }
    orderedPostIDs.push(match.post.postID);
  });

  const removeCandidates = Array.from(unmatched.values())
    .sort((left, right) => left.sourceSortIndex - right.sourceSortIndex)
    .map((post, index): ReconcileRemoveCandidateEntry => ({
      kind: "removeCandidate",
      postID: post.postID,
      sourceURL: post.sourceURL,
      previousIndex: post.sourceSortIndex,
      proposedIndex: input.candidates.length + index,
    }));
  const allPostIDs = Array.from(new Set([
    ...orderedPostIDs,
    ...removeCandidates.map((entry) => entry.postID),
  ]));
  const result = {
    keep,
    add,
    reorder,
    removeCandidates,
    orderedPostIDs,
    allPostIDs,
    resultingPostCount: allPostIDs.length,
  };
  return {
    ...result,
    snapshotHash: createHash("sha256")
      .update(JSON.stringify(result))
      .digest("hex")
      .slice(0, 40),
  };
}

function findMatch(
  candidate: ReconcileCandidate,
  existingPosts: ReconcileExistingPost[],
): {
  post: ReconcileExistingPost;
  matchedBy: "canonicalURL" | "contentHash";
} | null {
  const canonicalURL = canonicalCandidateURL(candidate.sourceURL);
  const urlMatch = existingPosts.find(
    (post) => canonicalCandidateURL(post.sourceURL) === canonicalURL,
  );
  if (urlMatch !== undefined) {
    return {post: urlMatch, matchedBy: "canonicalURL"};
  }
  if (candidate.contentHash === null) {
    return null;
  }
  const hashMatch = existingPosts.find(
    (post) => post.contentHash === candidate.contentHash,
  );
  return hashMatch === undefined ?
    null :
    {post: hashMatch, matchedBy: "contentHash"};
}

function deterministicRepairPostID(candidate: ReconcileCandidate): string {
  const identity = candidate.contentHash ??
    canonicalCandidateURL(candidate.sourceURL);
  return `repair_${createHash("sha256")
    .update(identity)
    .digest("hex")
    .slice(0, 24)}`;
}
