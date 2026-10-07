/* eslint-disable require-jsdoc */
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {db} from "../../../core/firebase.js";
import {FUNCTIONS_REGION} from "../../../core/runtime.js";
import {prepareNextQueueBatch} from "./preparation-runner.js";

export const onLookbookBatchPreparationRequested = onDocumentWritten(
  {region: FUNCTIONS_REGION, document: "lookbookImportBatches/{batchID}",
    retry: true, timeoutSeconds: 540},
  async (event) => {
    const after = event.data?.after.data();
    if (after?.state !== "preparing" || after.preparationOwner) return;
    await prepareNextQueueBatch(db);
  }
);

export const onLookbookPreparationSequenceChanged = onDocumentWritten(
  {region: FUNCTIONS_REGION, document: "lookbookImportQueue/main",
    retry: true, timeoutSeconds: 540},
  async (event) => {
    const after = event.data?.after.data();
    const before = event.data?.before.data();
    const recoveryCleared = before?.state === "recoveryRequired" &&
      after?.state !== "recoveryRequired";
    if (!after || before?.preparationSequence === after.preparationSequence &&
        !recoveryCleared) {
      return;
    }
    await prepareNextQueueBatch(db);
  }
);
