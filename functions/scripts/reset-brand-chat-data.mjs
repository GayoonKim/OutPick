import {
  assertApplyGate,
} from "../lib/developmentReset/brandChatManifest.js";
import {
  applyBrandChatReset,
  auditBrandChatReset,
} from "./brand-chat-reset-support.mjs";

function parseArguments(argv) {
  let apply = false;
  let projectID = null;
  let requestedHash = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--apply") {
      apply = true;
    } else if (argument === "--project") {
      projectID = argv[index + 1] ?? null;
      index += 1;
    } else if (argument === "--confirmation-hash") {
      requestedHash = argv[index + 1] ?? null;
      index += 1;
    } else {
      throw new Error(`지원하지 않는 인자입니다: ${argument}`);
    }
  }
  if (!apply) {
    throw new Error("실제 초기화에는 --apply가 필요합니다.");
  }
  if (!projectID?.trim()) {
    throw new Error("--project 값이 필요합니다.");
  }
  if (!requestedHash?.trim()) {
    throw new Error("--confirmation-hash 값이 필요합니다.");
  }
  return {
    projectID: projectID.trim(),
    requestedHash: requestedHash.trim(),
  };
}

const {projectID, requestedHash} = parseArguments(process.argv.slice(2));
const before = await auditBrandChatReset(projectID);
assertApplyGate({
  requestedProjectID: projectID,
  initializedProjectID: projectID,
  confirmationHash: requestedHash,
  expectedConfirmationHash: before.confirmationHash,
  unknownRootCollections: before.rootCollections.unknown,
  queueState: before.queue.state,
  queueTaskCount: before.queue.taskCount,
  processingImportJobCount: before.processingImportJobCount,
});

const deleted = await applyBrandChatReset(projectID);
const after = await auditBrandChatReset(projectID);
const remainingCount = [
  ...Object.values(after.deleteCounts.rootCollections),
  ...Object.values(after.deleteCounts.nestedCollections),
  ...Object.values(after.deleteCounts.userSubcollections),
  after.deleteCounts.usersWithLegacyChatFields,
  ...Object.values(after.deleteCounts.storage)
    .map((summary) => summary.objectCount),
].reduce((sum, count) => sum + count, 0);

console.log(JSON.stringify({deleted, after, remainingCount}, null, 2));
if (remainingCount !== 0) {
  throw new Error(`초기화 후 삭제 대상이 남아 있습니다: ${remainingCount}`);
}
console.log("브랜드·채팅 개발 데이터 초기화와 사후 0건 검증이 완료됐습니다.");
