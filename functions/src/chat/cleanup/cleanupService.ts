/* eslint-disable require-jsdoc */
export type ExpiredMediaUpload = {
  roomID: string | null;
  messageID: string;
  storagePrefix: string;
};

export type ChatMediaCleanupDependencies = {
  messageExists: (upload: ExpiredMediaUpload) => Promise<boolean>;
  deleteReservation: (upload: ExpiredMediaUpload) => Promise<void>;
  markCleanupFailed: (
    upload: ExpiredMediaUpload,
    reason: string
  ) => Promise<void>;
  deleteStoragePrefix: (upload: ExpiredMediaUpload) => Promise<void>;
  logDeleted: (upload: ExpiredMediaUpload) => void;
  logFailure: (upload: ExpiredMediaUpload, error: unknown) => void;
};

export function didRoomTransitionToClosed(
  before: {isClosed?: boolean} | undefined,
  after: {isClosed?: boolean} | undefined
): boolean {
  return before !== undefined &&
    after !== undefined &&
    !before.isClosed &&
    !!after.isClosed;
}

export async function cleanupExpiredMediaUploads(
  uploads: ExpiredMediaUpload[],
  dependencies: ChatMediaCleanupDependencies
): Promise<void> {
  for (const upload of uploads) {
    if (!upload.roomID || !upload.messageID || !upload.storagePrefix) {
      await dependencies.markCleanupFailed(upload, "invalid_reservation");
      continue;
    }

    const expectedPrefix =
      `rooms/${upload.roomID}/messages/${upload.messageID}`;
    if (upload.storagePrefix !== expectedPrefix) {
      await dependencies.markCleanupFailed(upload, "storage_prefix_mismatch");
      continue;
    }

    if (await dependencies.messageExists(upload)) {
      await dependencies.deleteReservation(upload);
      continue;
    }

    try {
      await dependencies.deleteStoragePrefix(upload);
      await dependencies.deleteReservation(upload);
      dependencies.logDeleted(upload);
    } catch (error) {
      dependencies.logFailure(upload, error);
      const reason = error instanceof Error ? error.message : String(error);
      await dependencies.markCleanupFailed(upload, reason);
    }
  }
}
