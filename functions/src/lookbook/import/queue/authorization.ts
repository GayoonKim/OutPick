/* eslint-disable require-jsdoc, valid-jsdoc */
import type {
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {
  hasActivePlatformAdminData,
} from "../../../shared/platformAuthorization.js";

export function queueAuthorization(db: Firestore) {
  return async (transaction: Transaction, uid: string, brandID: string) => {
    const brand = await transaction.get(db.doc(`brands/${brandID}`));
    const adminRef = db.doc(`platformAdmins/${uid}`);
    const platformAdmin = await transaction.get(adminRef);
    if (!brand.exists || (brand.data()?.deletionStatus &&
        brand.data()?.deletionStatus !== "active")) {
      throw new Error("TARGET_DELETED");
    }
    if (!hasActivePlatformAdminData(platformAdmin.data())) {
      throw new Error("PERMISSION_DENIED");
    }
  };
}

/** 접수된 작업의 내부 준비에서는 접수 당시 권한을 재검사하지 않는다.
 * @param db Firestore 인스턴스
 * @param transaction 현재 transaction
 * @param brandID 확인할 브랜드 ID
 * @return 브랜드가 활성 상태면 완료된다.
 */
export async function assertQueueBrandAvailable(
  db: Firestore,
  transaction: Transaction,
  brandID: string
): Promise<void> {
  const brand = await transaction.get(db.doc(`brands/${brandID}`));
  if (!brand.exists || (brand.data()?.deletionStatus &&
      brand.data()?.deletionStatus !== "active")) {
    throw new Error("TARGET_DELETED");
  }
}

// 일부 필드만 남은 큐 job도 기존 시즌별 전달/감시 경로로 되돌리지 않는다.
export function isBatchQueueJob(data: Record<string, unknown>): boolean {
  return data.queueContractVersion !== undefined ||
    data.queueBatchID !== undefined || data.dispatchMode === "batchQueue";
}
