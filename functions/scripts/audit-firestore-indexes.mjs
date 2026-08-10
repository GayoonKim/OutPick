import {execFileSync} from "node:child_process";
import {readFile} from "node:fs/promises";

function argument(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : null;
}

const projectID = argument("--project");
if (!projectID) throw new Error("--project가 필요합니다.");

const local = JSON.parse(await readFile(
  new URL("../../firestore.indexes.json", import.meta.url),
  "utf8",
));
const remote = JSON.parse(execFileSync(
  "firebase",
  ["firestore:indexes", "--project", projectID],
  {encoding: "utf8", stdio: ["ignore", "pipe", "inherit"]},
));

function canonicalFields(fields) {
  const result = fields.map((field) => ({
    fieldPath: field.fieldPath,
    ...(field.order ? {order: field.order} : {}),
    ...(field.arrayConfig ? {arrayConfig: field.arrayConfig} : {}),
  }));
  if (!result.some((field) => field.fieldPath === "__name__")) {
    const lastOrdered = [...result].reverse().find((field) => field.order);
    result.push({fieldPath: "__name__", order: lastOrdered?.order ?? "ASCENDING"});
  }
  return result;
}

function canonicalIndexes(value) {
  return value.map((index) => JSON.stringify({
    collectionGroup: index.collectionGroup,
    queryScope: index.queryScope,
    fields: canonicalFields(index.fields),
  })).sort();
}

function canonicalOverrides(value) {
  return value.map((override) => JSON.stringify({
    collectionGroup: override.collectionGroup,
    fieldPath: override.fieldPath,
    ttl: override.ttl === true,
    indexes: (override.indexes ?? []).map((index) => ({
      ...(index.order ? {order: index.order} : {}),
      ...(index.arrayConfig ? {arrayConfig: index.arrayConfig} : {}),
      queryScope: index.queryScope,
    })).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right))),
  })).sort();
}

function difference(left, right) {
  const rightSet = new Set(right);
  return left.filter((value) => !rightSet.has(value));
}

const localIndexes = canonicalIndexes(local.indexes ?? []);
const remoteIndexes = canonicalIndexes(remote.indexes ?? []);
const localOverrides = canonicalOverrides(local.fieldOverrides ?? []);
const remoteOverrides = canonicalOverrides(remote.fieldOverrides ?? []);
const result = {
  projectID,
  localIndexCount: localIndexes.length,
  remoteIndexCount: remoteIndexes.length,
  indexesOnlyLocalCount: difference(localIndexes, remoteIndexes).length,
  indexesOnlyRemoteCount: difference(remoteIndexes, localIndexes).length,
  localFieldOverrideCount: localOverrides.length,
  remoteFieldOverrideCount: remoteOverrides.length,
  fieldOverridesOnlyLocalCount: difference(localOverrides, remoteOverrides).length,
  fieldOverridesOnlyRemoteCount: difference(remoteOverrides, localOverrides).length,
};
console.log(JSON.stringify(result, null, 2));
if (Object.entries(result).some(([key, value]) => key.endsWith("OnlyLocalCount") ||
  key.endsWith("OnlyRemoteCount") ? value !== 0 : false)) {
  process.exitCode = 1;
}
