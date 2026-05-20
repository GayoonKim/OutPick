import {Timestamp, type Firestore} from "firebase-admin/firestore";
import type {Auth} from "firebase-admin/auth";
import {
  lookbookTestEmails,
  lookbookTestIDs,
  markerFields,
  upsertAuthUser,
  userProfileDocument
} from "./lookbookSeedSupport.js";

export interface LookbookBasicSeedRequest {
  readonly testRunId?: string;
}

export interface LookbookBasicSeedResult {
  readonly brandID: string;
  readonly seasonID: string;
  readonly postID: string;
  readonly userIDs: string[];
  readonly authUserEmails: string[];
  readonly testRunId?: string;
}

export async function seedLookbookBasic(
  firestore: Firestore,
  auth: Auth,
  password: string,
  request: LookbookBasicSeedRequest
): Promise<LookbookBasicSeedResult> {
  const {
    brandID,
    seasonID,
    postID,
    currentUserID,
    authorUserID
  } = lookbookTestIDs;
  const {
    currentUserEmail,
    authorUserEmail
  } = lookbookTestEmails;

  await upsertAuthUser(auth, currentUserID, currentUserEmail, password, "UI 테스트");
  await upsertAuthUser(auth, authorUserID, authorUserEmail, password, "UI 테스트 작성자");

  const now = Timestamp.fromDate(new Date("2026-05-20T00:00:00.000Z"));
  const marker = markerFields(request.testRunId);

  await firestore.collection("users").doc(currentUserID).set({
    ...userProfileDocument(currentUserEmail, "UI 테스트"),
    ...marker
  }, {merge: true});

  await firestore.collection("users").doc(authorUserID).set({
    ...userProfileDocument(authorUserEmail, "UI 테스트 작성자"),
    ...marker
  }, {merge: true});

  const brandRef = firestore.collection("brands").doc(brandID);
  const seasonRef = brandRef.collection("seasons").doc(seasonID);
  const postRef = seasonRef.collection("posts").doc(postID);

  await brandRef.set({
    name: "UI Test Brand",
    websiteURL: null,
    lookbookArchiveURL: null,
    logoPath: null,
    logoThumbPath: null,
    logoDetailPath: null,
    logoOriginalPath: null,
    isFeatured: true,
    discoveryStatus: "success",
    lastDiscoveryErrorMessage: null,
    lastDiscoveryRequestedAt: null,
    lastDiscoveryCompletedAt: null,
    likeCount: 0,
    viewCount: 0,
    popularScore: 0,
    updatedAt: now,
    ...marker
  }, {merge: true});

  await seasonRef.set({
    displayTitle: "UI Test Season",
    sourceTitle: null,
    year: 2026,
    term: "ss",
    coverPath: null,
    coverRemoteURL: null,
    description: "UI 테스트용 시즌",
    tagIDs: [],
    tagConceptIDs: [],
    status: "published",
    assetSyncStatus: "ready",
    metadataStatus: "confirmed",
    metadataConfidence: null,
    sourceURL: null,
    sourceImportJobID: null,
    sourceSortIndex: 0,
    postCount: 1,
    createdAt: now,
    updatedAt: now,
    ...marker
  }, {merge: true});

  await postRef.set({
    brandID,
    seasonID,
    authorID: authorUserID,
    media: [
      {
        type: "image",
        remoteURL: "https://example.com/outpick-uitest-look.jpg",
        thumbPath: null,
        detailPath: null,
        sourcePageURL: null,
        width: null,
        height: null
      }
    ],
    caption: "UI 테스트 룩",
    tagIDs: [],
    metrics: {
      likeCount: 3,
      commentCount: 0,
      replacementCount: 0,
      saveCount: 1,
      viewCount: 10
    },
    createdAt: now,
    updatedAt: now,
    ...marker
  }, {merge: true});

  return {
    brandID,
    seasonID,
    postID,
    userIDs: [currentUserID, authorUserID],
    authUserEmails: [currentUserEmail, authorUserEmail],
    testRunId: request.testRunId
  };
}
