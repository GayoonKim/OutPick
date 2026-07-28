/* eslint-disable require-jsdoc */
import {HttpsError} from "firebase-functions/v2/https";
import {db, firebaseAuth} from "../core/firebase.js";

export function hasBrandWriteAccessData(
  data: FirebaseFirestore.DocumentData | undefined
): boolean {
  const role = typeof data?.role === "string" ? data.role : "";
  return role === "owner" || role === "admin";
}

export function isBrandOwnerData(
  data: FirebaseFirestore.DocumentData | undefined
): boolean {
  return data?.role === "owner";
}

export async function isTotalBrandAdmin(uid: string): Promise<boolean> {
  const adminSnap = await db.collection("brandAdmins").doc(uid).get();
  return adminSnap.exists && adminSnap.data()?.isActive === true;
}

export async function assertBrandCreationAccess(uid: string): Promise<void> {
  if (!(await isTotalBrandAdmin(uid))) {
    throw new HttpsError("permission-denied", "총 관리자 권한이 없습니다.");
  }
}

export async function assertBrandWriteAccess(
  uid: string,
  brandID: string
): Promise<void> {
  const brandRef = db.collection("brands").doc(brandID);
  const adminRef = brandRef.collection("admins").doc(uid);
  const [brandSnap, totalAdmin, adminSnap] = await Promise.all([
    brandRef.get(),
    isTotalBrandAdmin(uid),
    adminRef.get(),
  ]);

  if (!brandSnap.exists) {
    throw new HttpsError("not-found", "브랜드를 찾을 수 없습니다.");
  }
  if (!totalAdmin && !hasBrandWriteAccessData(adminSnap.data())) {
    throw new HttpsError("permission-denied", "브랜드 수정 권한이 없습니다.");
  }
}

export async function brandAdminCapabilities(uid: string): Promise<{
  isTotalAdmin: boolean;
  roles: string[];
  ownedBrandIDs: string[];
  adminBrandIDs: string[];
}> {
  const adminRef = db.collection("brandAdmins").doc(uid);
  const adminSnap = await adminRef.get();
  const adminData = adminSnap.data();
  const roles = Array.isArray(adminData?.roles) ?
    adminData.roles
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.trim())
      .filter((value) => value.length > 0) :
    [];
  const isTotalAdmin = adminSnap.exists && adminData?.isActive === true;

  if (isTotalAdmin) {
    return {isTotalAdmin: true, roles, ownedBrandIDs: [], adminBrandIDs: []};
  }

  const brandManagersSnap = await db
    .collectionGroup("admins")
    .where("uid", "==", uid)
    .get();
  const ownedBrandIDs: string[] = [];
  const adminBrandIDs: string[] = [];
  brandManagersSnap.docs.forEach((doc) => {
    const data = doc.data();
    const brandID = typeof data.brandID === "string" ?
      data.brandID :
      doc.ref.parent.parent?.id ?? "";
    if (brandID.length === 0) return;
    if (data.role === "owner") ownedBrandIDs.push(brandID);
    else if (data.role === "admin") adminBrandIDs.push(brandID);
  });

  return {
    isTotalAdmin: false,
    roles: adminSnap.exists ? roles : [],
    ownedBrandIDs,
    adminBrandIDs,
  };
}

export async function assertOutPickAdmin(uid: string): Promise<void> {
  if (!(await isTotalBrandAdmin(uid))) {
    throw new HttpsError("permission-denied", "관리자 권한이 없습니다.");
  }
}

interface AuthUserLookup {
  getUserByEmail(email: string): Promise<{uid: string}>;
}

function errorCode(error: unknown): string {
  if (!error || typeof error !== "object" || !("code" in error)) return "";
  return typeof error.code === "string" ? error.code : "";
}

export async function findUserIDByEmail(
  email: string,
  auth: AuthUserLookup = firebaseAuth
): Promise<string> {
  try {
    return (await auth.getUserByEmail(email)).uid;
  } catch (error) {
    if (errorCode(error) === "auth/user-not-found") {
      throw new HttpsError(
        "not-found",
        "이메일에 해당하는 사용자를 찾을 수 없습니다."
      );
    }
    throw error;
  }
}
