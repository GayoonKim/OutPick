import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {
  styleMoodTermIndexID,
  styleMoodTerms,
  validateStyleMoodSeedEntries,
} from "../lib/styleMoods/policy.js";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const functionsDirectory = resolve(scriptDirectory, "..");
const seedPath = resolve(functionsDirectory, "seeds/style-moods.v1.json");

function parseArguments(argv) {
  let projectID = null;
  let apply = false;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") {
      apply = true;
    } else if (argument === "--project") {
      projectID = argv[index + 1] ?? null;
      index += 1;
    } else {
      throw new Error(`지원하지 않는 인자입니다: ${argument}`);
    }
  }

  if (!projectID || projectID.trim().length === 0) {
    throw new Error("--project 값이 필요합니다.");
  }
  return {projectID: projectID.trim(), apply};
}

function moodComparable(entry) {
  return {
    schemaVersion: entry.schemaVersion,
    displayName: entry.displayName,
    normalizedName: entry.normalizedName,
    displayGroup: entry.displayGroup,
    aliases: entry.aliases,
    sortOrder: entry.sortOrder,
    isFeaturedInOnboarding: entry.isFeaturedInOnboarding,
    status: entry.status,
  };
}

function storedMoodComparable(data) {
  return {
    schemaVersion: data?.schemaVersion,
    displayName: data?.displayName,
    normalizedName: data?.normalizedName,
    displayGroup: data?.displayGroup,
    aliases: data?.aliases,
    sortOrder: data?.sortOrder,
    isFeaturedInOnboarding: data?.isFeaturedInOnboarding,
    status: data?.status,
  };
}

function sameValue(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function buildPlan(entries, moodDocuments, termDocuments, metadata, contentHash) {
  const seededMoodIDs = new Set(entries.map((entry) => entry.moodID));
  const expectedTerms = new Map();

  for (const entry of entries) {
    for (const term of styleMoodTerms(entry)) {
      const indexID = styleMoodTermIndexID(term.normalizedTerm);
      expectedTerms.set(indexID, {
        moodID: entry.moodID,
        termType: term.termType,
      });
    }
  }

  for (const [indexID, expected] of expectedTerms) {
    const existing = termDocuments.get(indexID);
    if (existing && existing.moodID !== expected.moodID) {
      throw new Error(
        `용어 인덱스 충돌: ${indexID} ` +
        `(${existing.moodID} -> ${expected.moodID})`
      );
    }
  }

  const createMoods = [];
  const updateMoods = [];
  for (const entry of entries) {
    const existing = moodDocuments.get(entry.moodID);
    if (!existing) {
      createMoods.push(entry);
    } else if (
      !sameValue(storedMoodComparable(existing), moodComparable(entry))
    ) {
      updateMoods.push(entry);
    }
  }

  const upsertTerms = [];
  for (const [indexID, expected] of expectedTerms) {
    const existing = termDocuments.get(indexID);
    if (
      !existing ||
      existing.moodID !== expected.moodID ||
      existing.termType !== expected.termType
    ) {
      upsertTerms.push({indexID, ...expected, exists: Boolean(existing)});
    }
  }

  const deleteTermIDs = [];
  for (const [indexID, existing] of termDocuments) {
    if (
      seededMoodIDs.has(existing.moodID) &&
      !expectedTerms.has(indexID)
    ) {
      deleteTermIDs.push(indexID);
    }
  }

  const metadataChanged = !sameValue({
    version: metadata?.version,
    contentHash: metadata?.contentHash,
    count: metadata?.count,
  }, {
    version: 1,
    contentHash,
    count: entries.length,
  });

  return {
    createMoods,
    updateMoods,
    upsertTerms,
    deleteTermIDs,
    metadataChanged,
  };
}

function planSummary(plan) {
  return {
    createMoodCount: plan.createMoods.length,
    updateMoodCount: plan.updateMoods.length,
    upsertTermCount: plan.upsertTerms.length,
    deleteTermCount: plan.deleteTermIDs.length,
    metadataChanged: plan.metadataChanged,
  };
}

async function loadCurrentState(firestore) {
  const [moods, terms, metadata] = await Promise.all([
    firestore.collection("styleMoods").get(),
    firestore.collection("styleMoodTermIndex").get(),
    firestore.doc("styleMoodSeedMetadata/current").get(),
  ]);
  return {
    moodDocuments: new Map(
      moods.docs.map((document) => [document.id, document.data()])
    ),
    termDocuments: new Map(
      terms.docs.map((document) => [document.id, document.data()])
    ),
    metadata: metadata.data(),
  };
}

async function applyPlan(firestore, entries, contentHash) {
  return firestore.runTransaction(async (transaction) => {
    const [moods, terms, metadata] = await Promise.all([
      transaction.get(firestore.collection("styleMoods")),
      transaction.get(firestore.collection("styleMoodTermIndex")),
      transaction.get(firestore.doc("styleMoodSeedMetadata/current")),
    ]);
    const plan = buildPlan(
      entries,
      new Map(moods.docs.map((document) => [document.id, document.data()])),
      new Map(terms.docs.map((document) => [document.id, document.data()])),
      metadata.data(),
      contentHash
    );

    for (const entry of plan.createMoods) {
      transaction.set(firestore.collection("styleMoods").doc(entry.moodID), {
        ...moodComparable(entry),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    for (const entry of plan.updateMoods) {
      transaction.update(firestore.collection("styleMoods").doc(entry.moodID), {
        ...moodComparable(entry),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    for (const term of plan.upsertTerms) {
      const payload = {
        moodID: term.moodID,
        termType: term.termType,
      };
      transaction.set(
        firestore.collection("styleMoodTermIndex").doc(term.indexID),
        term.exists ?
          payload :
          {...payload, createdAt: FieldValue.serverTimestamp()},
        {merge: true}
      );
    }
    for (const indexID of plan.deleteTermIDs) {
      transaction.delete(
        firestore.collection("styleMoodTermIndex").doc(indexID)
      );
    }
    if (plan.metadataChanged) {
      transaction.set(firestore.doc("styleMoodSeedMetadata/current"), {
        version: 1,
        contentHash,
        count: entries.length,
        appliedAt: FieldValue.serverTimestamp(),
      });
    }
    return planSummary(plan);
  });
}

const {projectID, apply} = parseArguments(process.argv.slice(2));
const seedSource = await readFile(seedPath, "utf8");
const rawEntries = JSON.parse(seedSource);
const entries = validateStyleMoodSeedEntries(rawEntries);
if (entries.length !== 56) {
  throw new Error(`v1 seed 항목 수가 56개가 아닙니다: ${entries.length}`);
}
const contentHash = createHash("sha256")
  .update(JSON.stringify(entries))
  .digest("hex");

const app = getApps().length === 0 ?
  initializeApp({projectId: projectID}) :
  getApps()[0];
if (app.options.projectId !== projectID) {
  throw new Error(
    `초기화된 Firebase project가 요청과 다릅니다: ` +
    `${app.options.projectId} != ${projectID}`
  );
}
const firestore = getFirestore(app);
const current = await loadCurrentState(firestore);
const dryRunPlan = buildPlan(
  entries,
  current.moodDocuments,
  current.termDocuments,
  current.metadata,
  contentHash
);

console.log(JSON.stringify({
  mode: apply ? "apply" : "dry-run",
  projectID,
  seedVersion: 1,
  contentHash,
  entryCount: entries.length,
  ...planSummary(dryRunPlan),
}, null, 2));

if (apply) {
  const result = await applyPlan(firestore, entries, contentHash);
  console.log(JSON.stringify({applied: true, ...result}, null, 2));
} else {
  console.log("dry-run 완료: --apply가 없어 Firestore를 변경하지 않았습니다.");
}
