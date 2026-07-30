import {CloudTasksClient} from "@google-cloud/tasks";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {
  BRAND_CHAT_DELETE_NESTED_COLLECTIONS,
  BRAND_CHAT_DELETE_ROOT_COLLECTIONS,
  BRAND_CHAT_DELETE_STORAGE_PREFIXES,
  BRAND_CHAT_DELETE_USER_SUBCOLLECTIONS,
  BRAND_CHAT_PRESERVE_ROOT_COLLECTIONS,
  classifyRootCollections,
  confirmationHash,
  EXPECTED_DEVELOPMENT_PROJECT_ID,
  EXPECTED_DEVELOPMENT_STORAGE_BUCKET,
  LOOKBOOK_IMPORT_QUEUE_ID,
  LOOKBOOK_IMPORT_QUEUE_LOCATION,
} from "../lib/developmentReset/brandChatManifest.js";

const LEGACY_USER_FIELDS = ["joinedRooms", "roomStates"];

function queueStateName(state) {
  const states = {
    0: "STATE_UNSPECIFIED",
    1: "RUNNING",
    2: "PAUSED",
    3: "DISABLED",
  };
  return states[state] ?? String(state ?? "UNKNOWN");
}

async function countQuery(query) {
  const snapshot = await query.count().get();
  return snapshot.data().count;
}

async function countLegacyUserFields(firestore) {
  const snapshot = await firestore.collection("users").get();
  let count = 0;
  for (const document of snapshot.docs) {
    const data = document.data();
    if (LEGACY_USER_FIELDS.some((field) => data[field] !== undefined)) {
      count += 1;
    }
  }
  return count;
}

async function countProcessingImportJobs(firestore) {
  const snapshot = await firestore.collectionGroup("importJobs").get();
  return snapshot.docs.filter(
    (document) => document.data().status === "processing"
  ).length;
}

async function countAuthUsers(app) {
  const auth = getAuth(app);
  let count = 0;
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    count += page.users.length;
    pageToken = page.pageToken;
  } while (pageToken);
  return count;
}

async function storageSummary(bucket, prefix) {
  const [files] = await bucket.getFiles({prefix});
  let totalBytes = 0;
  for (const file of files) {
    const size = Number(file.metadata.size ?? 0);
    if (Number.isFinite(size)) {
      totalBytes += size;
    }
  }
  return {objectCount: files.length, totalBytes};
}

async function queueSummary(projectID) {
  const client = new CloudTasksClient();
  const name = client.queuePath(
    projectID,
    LOOKBOOK_IMPORT_QUEUE_LOCATION,
    LOOKBOOK_IMPORT_QUEUE_ID
  );
  try {
    const [[queue], [tasks]] = await Promise.all([
      client.getQueue({name}),
      client.listTasks({parent: name}),
    ]);
    return {
      name,
      exists: true,
      state: queueStateName(queue.state),
      taskCount: tasks.length,
    };
  } catch (error) {
    if (error?.code === 5) {
      return {name, exists: false, state: "NOT_FOUND", taskCount: 0};
    }
    throw error;
  } finally {
    await client.close();
  }
}

function initializeProject(projectID) {
  if (projectID !== EXPECTED_DEVELOPMENT_PROJECT_ID) {
    throw new Error(`허용되지 않은 Firebase project입니다: ${projectID}`);
  }
  const app = getApps().length === 0 ?
    initializeApp({
      projectId: projectID,
      storageBucket: EXPECTED_DEVELOPMENT_STORAGE_BUCKET,
    }) :
    getApps()[0];
  if (app.options.projectId !== projectID) {
    throw new Error(
      `초기화된 Firebase project가 요청과 다릅니다: ` +
      `${app.options.projectId} != ${projectID}`
    );
  }
  return app;
}

export async function auditBrandChatReset(projectID) {
  const app = initializeProject(projectID);
  const firestore = getFirestore(app);
  const bucket = getStorage(app).bucket(EXPECTED_DEVELOPMENT_STORAGE_BUCKET);
  const rootCollections = await firestore.listCollections();
  const rootCollectionIDs = rootCollections.map((collection) => collection.id);
  const rootClassification = classifyRootCollections(rootCollectionIDs);

  const rootCounts = {};
  for (const collectionID of BRAND_CHAT_DELETE_ROOT_COLLECTIONS) {
    rootCounts[collectionID] = rootCollectionIDs.includes(collectionID) ?
      await countQuery(firestore.collection(collectionID)) :
      0;
  }

  const preserveRootCounts = {};
  for (const collectionID of BRAND_CHAT_PRESERVE_ROOT_COLLECTIONS) {
    preserveRootCounts[collectionID] =
      rootCollectionIDs.includes(collectionID) ?
        await countQuery(firestore.collection(collectionID)) :
        0;
  }

  const userProjectionCounts = {};
  for (const collectionID of BRAND_CHAT_DELETE_USER_SUBCOLLECTIONS) {
    userProjectionCounts[collectionID] =
      await countQuery(firestore.collectionGroup(collectionID));
  }

  const nestedCollectionCounts = {};
  for (const collectionID of BRAND_CHAT_DELETE_NESTED_COLLECTIONS) {
    nestedCollectionCounts[collectionID] =
      await countQuery(firestore.collectionGroup(collectionID));
  }

  const storage = {};
  for (const prefix of BRAND_CHAT_DELETE_STORAGE_PREFIXES) {
    storage[prefix] = await storageSummary(bucket, prefix);
  }

  const queue = await queueSummary(projectID);
  const processingImportJobCount =
    await countProcessingImportJobs(firestore);
  const legacyUserFieldCount = await countLegacyUserFields(firestore);
  const manifestCore = {
    schemaVersion: 1,
    projectID,
    rootCollections: rootClassification,
    deleteCounts: {
      rootCollections: rootCounts,
      nestedCollections: nestedCollectionCounts,
      userSubcollections: userProjectionCounts,
      usersWithLegacyChatFields: legacyUserFieldCount,
      storage,
    },
    preserve: {
      firebaseAuthAccountCount: await countAuthUsers(app),
      rootCollections: preserveRootCounts,
    },
    queue,
    processingImportJobCount,
    applyBlockedReasons: [
      ...(rootClassification.unknown.length > 0 ?
        [`미분류 root collection: ${rootClassification.unknown.join(", ")}`] :
        []),
      ...(queue.state !== "PAUSED" ?
        [`queue 상태가 PAUSED가 아님: ${queue.state}`] :
        []),
      ...(queue.taskCount !== 0 ?
        [`queue task가 남아 있음: ${queue.taskCount}`] :
        []),
      ...(processingImportJobCount !== 0 ?
        [`processing import job이 남아 있음: ${processingImportJobCount}`] :
        []),
    ],
  };

  return {
    ...manifestCore,
    confirmationHash: confirmationHash(manifestCore),
  };
}

async function deleteCollectionGroup(firestore, collectionID) {
  const bulkWriter = firestore.bulkWriter();
  let deleted = 0;
  while (true) {
    const snapshot = await firestore.collectionGroup(collectionID)
      .limit(400)
      .get();
    if (snapshot.empty) break;
    for (const document of snapshot.docs) {
      bulkWriter.delete(document.ref);
      deleted += 1;
    }
    await bulkWriter.flush();
  }
  await bulkWriter.close();
  return deleted;
}

async function clearLegacyUserFields(firestore) {
  const snapshot = await firestore.collection("users").get();
  const bulkWriter = firestore.bulkWriter();
  let updated = 0;
  for (const document of snapshot.docs) {
    const data = document.data();
    const patch = {};
    for (const field of LEGACY_USER_FIELDS) {
      if (data[field] !== undefined) {
        patch[field] = FieldValue.delete();
      }
    }
    if (Object.keys(patch).length > 0) {
      bulkWriter.update(document.ref, patch);
      updated += 1;
    }
  }
  await bulkWriter.close();
  return updated;
}

export async function applyBrandChatReset(projectID) {
  const app = initializeProject(projectID);
  const firestore = getFirestore(app);
  const bucket = getStorage(app).bucket(EXPECTED_DEVELOPMENT_STORAGE_BUCKET);
  const deleted = {
    rootCollections: {},
    nestedCollections: {},
    userSubcollections: {},
    usersWithLegacyChatFields: 0,
    storagePrefixes: {},
  };

  for (const collectionID of BRAND_CHAT_DELETE_NESTED_COLLECTIONS) {
    deleted.nestedCollections[collectionID] =
      await deleteCollectionGroup(firestore, collectionID);
  }
  for (const collectionID of BRAND_CHAT_DELETE_USER_SUBCOLLECTIONS) {
    deleted.userSubcollections[collectionID] =
      await deleteCollectionGroup(firestore, collectionID);
  }
  deleted.usersWithLegacyChatFields =
    await clearLegacyUserFields(firestore);

  for (const collectionID of BRAND_CHAT_DELETE_ROOT_COLLECTIONS) {
    const reference = firestore.collection(collectionID);
    const count = await countQuery(reference);
    if (count > 0) {
      await firestore.recursiveDelete(reference);
    }
    deleted.rootCollections[collectionID] = count;
  }

  for (const prefix of BRAND_CHAT_DELETE_STORAGE_PREFIXES) {
    const summary = await storageSummary(bucket, prefix);
    if (summary.objectCount > 0) {
      await bucket.deleteFiles({prefix, force: true});
    }
    deleted.storagePrefixes[prefix] = summary.objectCount;
  }
  return deleted;
}
