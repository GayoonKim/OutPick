#!/usr/bin/env node

const admin = require("../../functions/node_modules/firebase-admin");

const PROJECT_ID = process.env.OUTPICK_FIREBASE_PROJECT_ID || "outpick-664ae";
const COMMIT = process.argv.includes("--commit");
const DRY_RUN = !COMMIT;

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT_ID,
});

const db = admin.firestore();
const {FieldValue} = admin.firestore;

function stringList(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === "string") : [];
}

async function commitBatch(ops) {
  if (ops.length === 0) {
    return;
  }
  if (DRY_RUN) {
    return;
  }

  for (let i = 0; i < ops.length; i += 400) {
    const batch = db.batch();
    ops.slice(i, i + 400).forEach((op) => op(batch));
    await batch.commit();
  }
}

async function userEmail(uid, cache) {
  if (cache.has(uid)) {
    return cache.get(uid);
  }
  const snap = await db.collection("users").doc(uid).get();
  const email = typeof snap.data()?.email === "string" ? snap.data().email : null;
  cache.set(uid, email);
  return email;
}

async function migrateBrandManagers(totalAdminUIDs) {
  const userEmailCache = new Map();
  const brandsSnap = await db.collection("brands").get();
  const ops = [];
  const summary = {
    brandsScanned: brandsSnap.size,
    ownerDocsToWrite: 0,
    adminDocsToWrite: 0,
    legacyBrandArraysToDelete: 0,
    totalAdminManagerUIDsSkipped: 0,
    ownerWinsOverAdmin: 0,
  };

  for (const brandDoc of brandsSnap.docs) {
    const data = brandDoc.data();
    const brandID = brandDoc.id;
    const owners = new Set(stringList(data.ownerUIDs));
    const admins = new Set(stringList(data.adminUIDs));
    const managerRoles = new Map();

    owners.forEach((uid) => {
      if (totalAdminUIDs.has(uid)) {
        summary.totalAdminManagerUIDsSkipped += 1;
        return;
      }
      managerRoles.set(uid, "owner");
    });

    admins.forEach((uid) => {
      if (totalAdminUIDs.has(uid)) {
        summary.totalAdminManagerUIDsSkipped += 1;
        return;
      }
      if (managerRoles.get(uid) === "owner") {
        summary.ownerWinsOverAdmin += 1;
        return;
      }
      managerRoles.set(uid, "admin");
    });

    for (const [uid, role] of managerRoles) {
      const email = await userEmail(uid, userEmailCache);
      const managerRef = brandDoc.ref.collection("admins").doc(uid);
      ops.push((batch) => {
        batch.set(managerRef, {
          uid,
          brandID,
          role,
          email,
          normalizedEmail: email,
          migratedFrom: "brands.ownerUIDs/adminUIDs",
          addedBy: data.createdBy ?? null,
          addedAt: data.createdAt ?? FieldValue.serverTimestamp(),
          updatedBy: data.updatedBy ?? null,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
      if (role === "owner") {
        summary.ownerDocsToWrite += 1;
      } else {
        summary.adminDocsToWrite += 1;
      }
    }

    if (Object.prototype.hasOwnProperty.call(data, "ownerUIDs") ||
        Object.prototype.hasOwnProperty.call(data, "adminUIDs")) {
      ops.push((batch) => {
        batch.update(brandDoc.ref, {
          ownerUIDs: FieldValue.delete(),
          adminUIDs: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      summary.legacyBrandArraysToDelete += 1;
    }
  }

  await commitBatch(ops);
  return summary;
}

async function cleanupBrandAdmins() {
  const snaps = await db.collection("brandAdmins").get();
  const totalAdminUIDs = new Set();
  const ops = [];
  const summary = {
    brandAdminDocsScanned: snaps.size,
    legacyAdminFieldsToDelete: 0,
    rolesToNormalize: 0,
  };

  snaps.docs.forEach((doc) => {
    const data = doc.data();
    if (data.isActive === true) {
      totalAdminUIDs.add(doc.id);
    }

    const roles = stringList(data.roles);
    const nextRoles = data.isActive === true ?
      Array.from(new Set([...roles.filter((role) => role !== "brandCreator"), "totalAdmin"])) :
      roles.filter((role) => role !== "brandCreator");

    const patch = {};
    let shouldPatch = false;

    if (Object.prototype.hasOwnProperty.call(data, "allowedBrandIDs")) {
      patch.allowedBrandIDs = FieldValue.delete();
      shouldPatch = true;
    }
    if (Object.prototype.hasOwnProperty.call(data, "canCreateBrands")) {
      patch.canCreateBrands = FieldValue.delete();
      shouldPatch = true;
    }
    if (JSON.stringify(roles) !== JSON.stringify(nextRoles)) {
      patch.roles = nextRoles;
      shouldPatch = true;
      summary.rolesToNormalize += 1;
    }

    if (shouldPatch) {
      ops.push((batch) => batch.update(doc.ref, patch));
      summary.legacyAdminFieldsToDelete += 1;
    }
  });

  await commitBatch(ops);
  return {totalAdminUIDs, summary};
}

async function main() {
  console.log(`[brand-admin-migration] project=${PROJECT_ID} mode=${DRY_RUN ? "dry-run" : "commit"}`);

  const {totalAdminUIDs, summary: adminSummary} = await cleanupBrandAdmins();
  const brandSummary = await migrateBrandManagers(totalAdminUIDs);

  console.log(JSON.stringify({
    mode: DRY_RUN ? "dry-run" : "commit",
    totalAdminUIDs: Array.from(totalAdminUIDs).sort(),
    adminSummary,
    brandSummary,
  }, null, 2));

  if (DRY_RUN) {
    console.log("[brand-admin-migration] no writes performed. Re-run with --commit to apply.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("[brand-admin-migration] failed", error);
    process.exit(1);
  });
