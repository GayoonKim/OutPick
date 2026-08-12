/* eslint-disable max-len */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db} from "../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../core/runtime.js";
import {
  dueRoomOwnershipSuccessionJobIDs,
  processRoomOwnershipSuccessionJob,
} from "./roomMembershipSweep.js";

export const onRoomOwnershipSuccessionQueued = onDocumentCreated(
  {document: "roomOwnershipSuccessionJobs/{jobID}", region: FUNCTIONS_REGION},
  async (event) => {
    await processRoomOwnershipSuccessionJob(event.params.jobID);
  },
);

export const drainRoomOwnershipSuccessionJobs = onSchedule(
  {
    schedule: "every 5 minutes",
    region: FUNCTIONS_REGION,
    timeZone: "Asia/Seoul",
  },
  async () => {
    const jobIDs = await dueRoomOwnershipSuccessionJobIDs(db);
    for (const jobID of jobIDs) {
      await processRoomOwnershipSuccessionJob(jobID, db);
    }
  },
);
