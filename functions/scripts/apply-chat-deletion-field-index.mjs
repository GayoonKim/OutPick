import {GoogleAuth} from "google-auth-library";

const PROJECT_ID = "outpick-test";
const CONFIRMATION = "APPLY_CHAT_DELETION_INDEX_TO_OUTPICK_TEST";
const FIELD_PATH = "replyPreview.messageID";
const COLLECTION_GROUP = "Messages";
const DESIRED_SCOPES = ["COLLECTION", "COLLECTION_GROUP"];

function parseArguments(argv) {
  const projectIndex = argv.indexOf("--project");
  const confirmIndex = argv.indexOf("--confirm");
  return {
    projectID: projectIndex >= 0 ? argv[projectIndex + 1] : "",
    apply: argv.includes("--apply"),
    confirmation: confirmIndex >= 0 ? argv[confirmIndex + 1] : null,
  };
}

function normalizedScopes(indexConfig) {
  const scopes = [];
  for (const index of indexConfig?.indexes ?? []) {
    const field = index?.fields?.[0];
    if (field?.fieldPath !== FIELD_PATH || field?.order !== "ASCENDING" ||
        !DESIRED_SCOPES.includes(index.queryScope)) {
      throw new Error("기존 field override에 예상하지 않은 index 설정이 있습니다.");
    }
    scopes.push(index.queryScope);
  }
  return [...new Set(scopes)].sort();
}

function desiredIndexes() {
  return DESIRED_SCOPES.map((queryScope) => ({
    queryScope,
    fields: [{fieldPath: FIELD_PATH, order: "ASCENDING"}],
  }));
}

const options = parseArguments(process.argv.slice(2));
if (options.projectID !== PROJECT_ID) {
  throw new Error("이 exact index 도구는 outpick-test Development에서만 실행할 수 있습니다.");
}
if (options.apply && options.confirmation !== CONFIRMATION) {
  throw new Error(`apply에는 --confirm ${CONFIRMATION}가 필요합니다.`);
}

const auth = new GoogleAuth({scopes: ["https://www.googleapis.com/auth/cloud-platform"]});
const client = await auth.getClient();
const fieldName = `projects/${PROJECT_ID}/databases/(default)/collectionGroups/${COLLECTION_GROUP}/fields/${FIELD_PATH}`;
const fieldURL = `https://firestore.googleapis.com/v1/${fieldName}`;
const current = await client.request({url: fieldURL, method: "GET"});
const currentScopes = normalizedScopes(current.data.indexConfig);
const desiredScopes = [...DESIRED_SCOPES].sort();
const alreadyApplied = JSON.stringify(currentScopes) === JSON.stringify(desiredScopes);

console.log(JSON.stringify({
  mode: options.apply ? "apply" : "dry-run",
  projectID: PROJECT_ID,
  field: `${COLLECTION_GROUP}.${FIELD_PATH}`,
  currentScopes,
  desiredScopes,
  alreadyApplied,
}, null, 2));

if (!options.apply || alreadyApplied) process.exit(0);

const operation = await client.request({
  url: fieldURL,
  method: "PATCH",
  params: {updateMask: "indexConfig"},
  data: {
    name: fieldName,
    indexConfig: {indexes: desiredIndexes()},
  },
});
const operationName = operation.data.name;
if (typeof operationName !== "string" || operationName.length === 0) {
  throw new Error("Firestore field update operation 이름이 없습니다.");
}

for (let attempt = 0; attempt < 200; attempt += 1) {
  const status = await client.request({
    url: `https://firestore.googleapis.com/v1/${operationName}`,
    method: "GET",
  });
  if (status.data.done === true) {
    if (status.data.error) throw new Error(`Firestore field update 실패: ${status.data.error.code}`);
    console.log("Development field index update operation 완료");
    process.exit(0);
  }
  await new Promise((resolve) => setTimeout(resolve, 3_000));
}
throw new Error("Firestore field update operation timeout");
