/* eslint-disable require-jsdoc, valid-jsdoc */
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  optionalString,
  recordData,
  requiredAuthUID,
  requiredBoolean,
  requiredDocumentID,
  requiredString,
} from "../../core/callable.js";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  assertBrandCreationAccess,
  assertBrandWriteAccess,
  brandAdminCapabilities,
  findUserIDByEmail,
  hasBrandWriteAccessData,
  isBrandOwnerData,
  isTotalBrandAdmin,
} from "../../shared/brandAuthorization.js";
import {
  canonicalBrandName,
  normalizedBrandName,
  normalizedHTTPURL,
} from "../../shared/brandValidation.js";

type BrandManagerRole = "owner" | "admin";

function numericRootValue(
  data: FirebaseFirestore.DocumentData | undefined,
  key: string
): number {
  const value = data?.[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function timestampToISO(value: unknown): string | null {
  return value instanceof admin.firestore.Timestamp ?
    value.toDate().toISOString() : null;
}

function brandSearchSummary(
  brandID: string,
  data: FirebaseFirestore.DocumentData | undefined
): Record<string, unknown> {
  return {
    brandID,
    name: typeof data?.name === "string" ? data.name : "",
    englishName: typeof data?.englishName === "string" ?
      data.englishName : null,
    websiteURL: typeof data?.websiteURL === "string" ? data.websiteURL : null,
    lookbookArchiveURL: typeof data?.lookbookArchiveURL === "string" ?
      data.lookbookArchiveURL : null,
    logoThumbPath: typeof data?.logoThumbPath === "string" ?
      data.logoThumbPath :
      (typeof data?.logoPath === "string" ? data.logoPath : null),
    logoDetailPath: typeof data?.logoDetailPath === "string" ?
      data.logoDetailPath : null,
    logoOriginalPath: typeof data?.logoOriginalPath === "string" ?
      data.logoOriginalPath : null,
    isFeatured: data?.isFeatured === true,
    discoveryStatus: typeof data?.discoveryStatus === "string" ?
      data.discoveryStatus : "idle",
    deletionStatus: typeof data?.deletionStatus === "string" ?
      data.deletionStatus : "active",
    lastDiscoveryErrorMessage:
      typeof data?.lastDiscoveryErrorMessage === "string" ?
        data.lastDiscoveryErrorMessage : null,
    lastDiscoveryRequestedAt: timestampToISO(data?.lastDiscoveryRequestedAt),
    lastDiscoveryCompletedAt: timestampToISO(data?.lastDiscoveryCompletedAt),
    metrics: {
      likeCount: numericRootValue(data, "likeCount"),
      viewCount: numericRootValue(data, "viewCount"),
      popularScore: numericRootValue(data, "popularScore"),
    },
    updatedAt: timestampToISO(data?.updatedAt),
  };
}

export function validateBrandLogoPath(
  brandID: string,
  path: string | null,
  fileName: "thumb.jpg" | "detail.jpg"
): void {
  if (path === null) {
    return;
  }

  const expected = `brands/${brandID}/logo/${fileName}`;
  if (path !== expected) {
    throw new HttpsError(
      "invalid-argument",
      `${fileName} 경로가 brandID와 일치하지 않습니다.`
    );
  }
}
export function normalizedEmail(rawValue: string): string {
  const email = rawValue.trim().toLocaleLowerCase();
  if (
    email.length === 0 ||
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new HttpsError("invalid-argument", "email 값이 올바르지 않습니다.");
  }
  return email;
}

export function requiredBrandManagerRole(rawValue: string): BrandManagerRole {
  const role = rawValue.trim() as BrandManagerRole;
  if (role !== "owner" && role !== "admin") {
    throw new HttpsError("invalid-argument", "role 값이 올바르지 않습니다.");
  }
  return role;
}

export function optionalHTTPURLPatch(
  data: Record<string, unknown>,
  key: string
): string | null | undefined {
  if (!Object.prototype.hasOwnProperty.call(data, key)) {
    return undefined;
  }
  const rawValue = optionalString(data, key, 2048);
  if (rawValue === null) {
    return null;
  }
  return normalizedHTTPURL(rawValue, key);
}

function hasBooleanPatch(
  data: Record<string, unknown>,
  key: string
): boolean {
  return Object.prototype.hasOwnProperty.call(data, key);
}
function brandNameIndexEntries(
  normalizedName: string,
  normalizedEnglishName: string | null
): {key: string; source: "name" | "englishName"}[] {
  const entries: {key: string; source: "name" | "englishName"}[] = [
    {key: normalizedName, source: "name"},
  ];
  if (
    normalizedEnglishName !== null &&
    normalizedEnglishName.length > 0 &&
    normalizedEnglishName !== normalizedName
  ) {
    entries.push({key: normalizedEnglishName, source: "englishName"});
  }
  return entries;
}
export const getBrandAdminCapabilities = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const capabilities = await brandAdminCapabilities(uid);

    return {
      isTotalAdmin: capabilities.isTotalAdmin,
      roles: capabilities.roles,
      ownedBrandIDs: capabilities.ownedBrandIDs,
      adminBrandIDs: capabilities.adminBrandIDs,
    };
  }
);

export const createBrand = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const name = canonicalBrandName(requiredString(data, "name", 80));
    const normalizedName = normalizedBrandName(name);
    const englishNameInput = optionalString(data, "englishName", 80);
    const englishName = englishNameInput === null ?
      null :
      canonicalBrandName(englishNameInput);
    const normalizedEnglishName = englishName === null ?
      null :
      normalizedBrandName(englishName);
    const isFeatured = data.isFeatured === true;
    const websiteURLInput = optionalString(data, "websiteURL", 2048);
    const websiteURL = websiteURLInput ?
      normalizedHTTPURL(websiteURLInput, "websiteURL") :
      null;
    const lookbookArchiveURLInput = optionalString(
      data,
      "lookbookArchiveURL",
      2048
    );
    const lookbookArchiveURL = lookbookArchiveURLInput ?
      normalizedHTTPURL(lookbookArchiveURLInput, "lookbookArchiveURL") :
      null;

    await assertBrandCreationAccess(uid);

    const brandRef = db.collection("brands").doc();
    const brandID = brandRef.id;
    const nameIndexEntries = brandNameIndexEntries(
      normalizedName,
      normalizedEnglishName
    );
    const nameIndexRefs = nameIndexEntries.map((entry) =>
      db.collection("brandNameIndex").doc(entry.key)
    );

    await db.runTransaction(async (transaction) => {
      const nameIndexSnaps = await Promise.all(
        nameIndexRefs.map((ref) => transaction.get(ref))
      );
      if (nameIndexSnaps.some((snap) => snap.exists)) {
        throw new HttpsError("already-exists", "이미 존재하는 브랜드명입니다.");
      }

      transaction.set(brandRef, {
        name,
        normalizedName,
        englishName,
        normalizedEnglishName,
        websiteURL,
        lookbookArchiveURL,
        logoPath: null,
        logoThumbPath: null,
        logoDetailPath: null,
        logoOriginalPath: null,
        isFeatured,
        discoveryStatus: "idle",
        lastDiscoveryErrorMessage: null,
        lastDiscoveryRequestedAt: null,
        lastDiscoveryCompletedAt: null,
        likeCount: 0,
        viewCount: 0,
        popularScore: 0,
        createdBy: uid,
        updatedBy: uid,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      nameIndexRefs.forEach((ref, index) => {
        const entry = nameIndexEntries[index];
        transaction.set(ref, {
          brandID,
          name,
          normalizedName,
          englishName,
          normalizedEnglishName,
          source: entry.source,
          createdBy: uid,
          createdAt: FieldValue.serverTimestamp(),
        });
      });
    });

    return {brandID};
  }
);

export const updateBrand = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const hasNamePatch = Object.prototype.hasOwnProperty.call(data, "name");
    const name = hasNamePatch ?
      canonicalBrandName(requiredString(data, "name", 80)) :
      null;
    const normalizedName = name === null ? null : normalizedBrandName(name);
    const hasEnglishNamePatch = Object.prototype.hasOwnProperty.call(
      data,
      "englishName"
    );
    const englishNamePatch = hasEnglishNamePatch ?
      optionalString(data, "englishName", 80) :
      null;
    const englishName = !hasEnglishNamePatch || englishNamePatch === null ?
      null :
      canonicalBrandName(englishNamePatch);
    const normalizedEnglishName = !hasEnglishNamePatch || englishName === null ?
      null :
      normalizedBrandName(englishName);
    const websiteURL = optionalHTTPURLPatch(data, "websiteURL");
    const lookbookArchiveURL = optionalHTTPURLPatch(data, "lookbookArchiveURL");
    const hasFeaturedPatch = hasBooleanPatch(data, "isFeatured");
    const isFeatured = hasFeaturedPatch ?
      requiredBoolean(data, "isFeatured") :
      null;

    if (
      !hasNamePatch &&
      !hasEnglishNamePatch &&
      websiteURL === undefined &&
      lookbookArchiveURL === undefined &&
      !hasFeaturedPatch
    ) {
      throw new HttpsError("invalid-argument", "수정할 브랜드 필드가 없습니다.");
    }

    const isTotalAdmin = await isTotalBrandAdmin(uid);
    if (hasFeaturedPatch && !isTotalAdmin) {
      throw new HttpsError("permission-denied", "피처드 수정 권한이 없습니다.");
    }

    const brandRef = db.collection("brands").doc(brandID);
    const managerRef = brandRef.collection("admins").doc(uid);

    await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      const brandData = brandSnap.data();
      let hasWriteAccess = isTotalAdmin;
      if (!hasWriteAccess) {
        const managerSnap = await transaction.get(managerRef);
        hasWriteAccess = hasBrandWriteAccessData(managerSnap.data());
      }
      if (!hasWriteAccess) {
        throw new HttpsError("permission-denied", "브랜드 수정 권한이 없습니다.");
      }

      const patch: Record<string, unknown> = {
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (
        (hasNamePatch && name !== null && normalizedName !== null) ||
        hasEnglishNamePatch
      ) {
        const nextName = name ?? (
          typeof brandData?.name === "string" ? brandData.name : ""
        );
        const nextNormalizedName = normalizedName ?? (
          typeof brandData?.normalizedName === "string" ?
            brandData.normalizedName :
            normalizedBrandName(nextName)
        );
        const nextEnglishName = hasEnglishNamePatch ?
          englishName :
          (typeof brandData?.englishName === "string" ?
            brandData.englishName :
            null);
        const nextNormalizedEnglishName = hasEnglishNamePatch ?
          normalizedEnglishName :
          (typeof brandData?.normalizedEnglishName === "string" ?
            brandData.normalizedEnglishName :
            null);
        const previousNormalizedName =
          typeof brandData?.normalizedName === "string" ?
            brandData.normalizedName :
            "";
        const previousNormalizedEnglishName =
          typeof brandData?.normalizedEnglishName === "string" ?
            brandData.normalizedEnglishName :
            null;
        const previousIndexKeys = new Set(
          brandNameIndexEntries(
            previousNormalizedName,
            previousNormalizedEnglishName
          ).map((entry) => entry.key)
        );
        const nextIndexEntries = brandNameIndexEntries(
          nextNormalizedName,
          nextNormalizedEnglishName
        );
        const nextIndexKeys = new Set(
          nextIndexEntries.map((entry) => entry.key)
        );
        const refsToCheck = nextIndexEntries
          .filter((entry) => !previousIndexKeys.has(entry.key))
          .map((entry) => db.collection("brandNameIndex").doc(entry.key));
        const newNameIndexSnaps = await Promise.all(
          refsToCheck.map((ref) => transaction.get(ref))
        );
        if (
          newNameIndexSnaps.some((snap) =>
            snap.exists && snap.get("brandID") !== brandID
          )
        ) {
          throw new HttpsError("already-exists", "이미 존재하는 브랜드명입니다.");
        }

        for (const previousKey of previousIndexKeys) {
          if (!nextIndexKeys.has(previousKey)) {
            transaction.delete(
              db.collection("brandNameIndex").doc(previousKey)
            );
          }
        }

        for (const entry of nextIndexEntries) {
          const indexRef = db.collection("brandNameIndex").doc(entry.key);
          transaction.set(indexRef, {
            brandID,
            name: nextName,
            normalizedName: nextNormalizedName,
            englishName: nextEnglishName,
            normalizedEnglishName: nextNormalizedEnglishName,
            source: entry.source,
            updatedBy: uid,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }

        if (hasNamePatch && name !== null && normalizedName !== null) {
          patch.name = name;
          patch.normalizedName = normalizedName;
        }
        if (hasEnglishNamePatch) {
          patch.englishName = englishName;
          patch.normalizedEnglishName = normalizedEnglishName;
        }
      }

      if (websiteURL !== undefined) {
        patch.websiteURL = websiteURL;
      }
      if (lookbookArchiveURL !== undefined) {
        patch.lookbookArchiveURL = lookbookArchiveURL;
      }
      if (isFeatured !== null) {
        patch.isFeatured = isFeatured;
      }

      transaction.update(brandRef, patch);
    });

    const updatedBrandSnap = await brandRef.get();
    return {
      brandID,
      brand: brandSearchSummary(brandID, updatedBrandSnap.data()),
    };
  }
);

export const addBrandManager = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const email = normalizedEmail(requiredString(data, "email", 254));
    const role = requiredBrandManagerRole(requiredString(data, "role", 16));
    const targetUID = await findUserIDByEmail(email);
    const isTotalAdmin = await isTotalBrandAdmin(uid);
    const brandRef = db.collection("brands").doc(brandID);
    const callerManagerRef = brandRef.collection("admins").doc(uid);
    const targetManagerRef = brandRef.collection("admins").doc(targetUID);

    const result = await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      let callerIsOwner = false;
      if (!isTotalAdmin) {
        const callerManagerSnap = await transaction.get(callerManagerRef);
        callerIsOwner = isBrandOwnerData(callerManagerSnap.data());
      }

      if (!isTotalAdmin) {
        if (!callerIsOwner) {
          throw new HttpsError("permission-denied", "관리자 추가 권한이 없습니다.");
        }
        if (role === "owner") {
          throw new HttpsError("permission-denied", "owner 추가 권한이 없습니다.");
        }
      }

      const targetManagerSnap = await transaction.get(targetManagerRef);
      const currentRole =
        typeof targetManagerSnap.data()?.role === "string" ?
          targetManagerSnap.data()?.role :
          null;
      let duplicate = currentRole === role;

      if (role === "owner") {
        transaction.set(targetManagerRef, {
          uid: targetUID,
          brandID,
          role,
          email,
          normalizedEmail: email,
          addedBy: targetManagerSnap.exists ?
            targetManagerSnap.data()?.addedBy ?? uid :
            uid,
          addedAt: targetManagerSnap.exists ?
            targetManagerSnap.data()?.addedAt ?? FieldValue.serverTimestamp() :
            FieldValue.serverTimestamp(),
          updatedBy: uid,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      } else {
        if (currentRole === "owner") {
          duplicate = true;
        } else {
          transaction.set(targetManagerRef, {
            uid: targetUID,
            brandID,
            role,
            email,
            normalizedEmail: email,
            addedBy: targetManagerSnap.exists ?
              targetManagerSnap.data()?.addedBy ?? uid :
              uid,
            addedAt: targetManagerSnap.exists ?
              targetManagerSnap.data()?.addedAt ??
                FieldValue.serverTimestamp() :
              FieldValue.serverTimestamp(),
            updatedBy: uid,
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }

      transaction.update(brandRef, {
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {targetUID, duplicate};
    });

    return {
      brandID,
      uid: result.targetUID,
      email,
      role,
      duplicate: result.duplicate,
    };
  }
);

export const removeBrandManager = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const email = normalizedEmail(requiredString(data, "email", 254));
    const role = requiredBrandManagerRole(requiredString(data, "role", 16));
    const targetUID = await findUserIDByEmail(email);
    const isTotalAdmin = await isTotalBrandAdmin(uid);
    const brandRef = db.collection("brands").doc(brandID);
    const callerManagerRef = brandRef.collection("admins").doc(uid);
    const targetManagerRef = brandRef.collection("admins").doc(targetUID);

    const result = await db.runTransaction(async (transaction) => {
      const brandSnap = await transaction.get(brandRef);
      if (!brandSnap.exists) {
        throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
      }

      let callerIsOwner = false;
      if (!isTotalAdmin) {
        const callerManagerSnap = await transaction.get(callerManagerRef);
        callerIsOwner = isBrandOwnerData(callerManagerSnap.data());
      }

      if (!isTotalAdmin) {
        if (!callerIsOwner) {
          throw new HttpsError("permission-denied", "관리자 삭제 권한이 없습니다.");
        }
        if (role === "owner") {
          throw new HttpsError("permission-denied", "owner 삭제 권한이 없습니다.");
        }
      }

      const targetManagerSnap = await transaction.get(targetManagerRef);
      const currentRole =
        typeof targetManagerSnap.data()?.role === "string" ?
          targetManagerSnap.data()?.role :
          null;
      let removed = false;

      if (currentRole === role) {
        removed = true;
      }

      if (removed && role === "owner") {
        const ownerQuerySnap = await transaction.get(
          brandRef.collection("admins")
            .where("role", "==", "owner")
            .limit(2)
        );
        const hasOtherOwner = ownerQuerySnap.docs.some((doc) => {
          return doc.id !== targetUID;
        });
        if (!hasOtherOwner) {
          throw new HttpsError(
            "failed-precondition",
            "마지막 owner는 삭제할 수 없습니다."
          );
        }
      }

      if (removed) {
        transaction.delete(targetManagerRef);
      }

      transaction.update(brandRef, {
        updatedBy: uid,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {targetUID, removed};
    });

    return {
      brandID,
      uid: result.targetUID,
      email,
      role,
      removed: result.removed,
    };
  }
);

export const updateBrandLogoPaths = onCall(
  {region: FUNCTIONS_REGION},
  async (request) => {
    const uid = requiredAuthUID(request.auth?.uid);
    const data = recordData(request.data);

    const brandID = requiredDocumentID(
      requiredString(data, "brandID", 128),
      "brandID"
    );
    const logoThumbPath = optionalString(data, "logoThumbPath", 512);
    const logoDetailPath = optionalString(data, "logoDetailPath", 512);

    if (logoThumbPath === null && logoDetailPath === null) {
      throw new HttpsError(
        "invalid-argument",
        "업데이트할 로고 경로가 없습니다."
      );
    }

    validateBrandLogoPath(brandID, logoThumbPath, "thumb.jpg");
    validateBrandLogoPath(brandID, logoDetailPath, "detail.jpg");

    await assertBrandWriteAccess(uid, brandID);

    const patch: Record<string, unknown> = {
      updatedBy: uid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (logoThumbPath !== null) {
      patch.logoPath = logoThumbPath;
      patch.logoThumbPath = logoThumbPath;
    }
    if (logoDetailPath !== null) {
      patch.logoDetailPath = logoDetailPath;
    }

    await db.collection("brands").doc(brandID).update(patch);

    return {brandID};
  }
);
