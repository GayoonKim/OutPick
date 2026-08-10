import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import {GoogleAuth} from "google-auth-library";

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

const projectID = argument("--project");
if (!projectID) throw new Error("--project가 필요합니다.");

const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform.read-only"],
});
const client = await auth.getClient();

async function api(path) {
  const response = await client.request({
    url: `https://firebaserules.googleapis.com/v1/${path}`,
  });
  return response.data;
}

function sha256(content) {
  return createHash("sha256").update(content).digest("hex");
}

const releases = await api(`projects/${projectID}/releases?pageSize=100`);
const targets = [
  {suffix: "releases/cloud.firestore", localPath: "../../firestore.rules"},
  {suffix: `releases/firebase.storage/${projectID}.appspot.com`, localPath: "../../storage.rules"},
];
const results = [];

for (const target of targets) {
  const release = (releases.releases ?? []).find(
    (candidate) => candidate.name?.endsWith(target.suffix),
  );
  if (!release?.rulesetName) {
    throw new Error(`${target.suffix} release를 찾지 못했습니다.`);
  }
  const ruleset = await api(release.rulesetName);
  const remoteSource = (ruleset.source?.files ?? [])
    .map((file) => file.content ?? "")
    .join("\n");
  const localSource = await readFile(new URL(target.localPath, import.meta.url), "utf8");
  results.push({
    release: release.name,
    ruleset: release.rulesetName,
    remoteSHA256: sha256(remoteSource),
    localSHA256: sha256(localSource),
    matchesLocal: remoteSource === localSource,
  });
}

console.log(JSON.stringify({projectID, results}, null, 2));
