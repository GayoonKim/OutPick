import type {CollectionReference, DocumentReference, Firestore} from "firebase-admin/firestore";

const defaultIDPrefix = "uitest-";
const defaultBatchSize = 100;

export interface ResetRequest {
  readonly testRunId?: string;
  readonly dryRun?: boolean;
}

export interface ResetResult {
  readonly dryRun: boolean;
  readonly matchedDocumentPaths: string[];
  readonly deletedDocumentCount: number;
}

interface ResetTarget {
  readonly collectionPath: string;
}

const resetTargets: ResetTarget[] = [
  {collectionPath: "brands"},
  {collectionPath: "users"}
];

export async function resetFirestoreTestData(
  db: Firestore,
  request: ResetRequest
): Promise<ResetResult> {
  const matchedDocumentPaths: string[] = [];

  for (const target of resetTargets) {
    const snap = await db.collection(target.collectionPath).get();
    for (const doc of snap.docs) {
      if (shouldResetDocument(doc.id, request.testRunId)) {
        matchedDocumentPaths.push(doc.ref.path);
      }
    }
  }

  if (request.dryRun === true) {
    return {
      dryRun: true,
      matchedDocumentPaths,
      deletedDocumentCount: 0
    };
  }

  let deletedDocumentCount = 0;
  for (const path of matchedDocumentPaths) {
    deletedDocumentCount += await deleteDocumentTree(db.doc(path));
  }

  return {
    dryRun: false,
    matchedDocumentPaths,
    deletedDocumentCount
  };
}

function shouldResetDocument(documentID: string, testRunId: string | undefined): boolean {
  if (documentID.startsWith(defaultIDPrefix)) {
    return true;
  }

  const normalizedTestRunId = testRunId?.trim() ?? "";
  return normalizedTestRunId.length > 0 && documentID.includes(normalizedTestRunId);
}

async function deleteDocumentTree(documentRef: DocumentReference): Promise<number> {
  let deletedCount = 0;

  const childCollections = await documentRef.listCollections();
  for (const collectionRef of childCollections) {
    deletedCount += await deleteCollection(collectionRef);
  }

  await documentRef.delete();
  return deletedCount + 1;
}

async function deleteCollection(collectionRef: CollectionReference): Promise<number> {
  let deletedCount = 0;

  while (true) {
    const snap = await collectionRef.limit(defaultBatchSize).get();
    if (snap.empty) {
      break;
    }

    for (const doc of snap.docs) {
      deletedCount += await deleteDocumentTree(doc.ref);
    }
  }

  return deletedCount;
}
