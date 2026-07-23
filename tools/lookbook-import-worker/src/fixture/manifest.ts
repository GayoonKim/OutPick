import {readFile, readdir} from "node:fs/promises";
import {join, resolve, sep} from "node:path";

import type {
  ExpectedCandidateSpec,
  FixtureCase,
  FixtureExpected,
  FixtureMetadata,
} from "./types.js";

const SENSITIVE_QUERY_KEY_PATTERN =
  /token|auth|key|signature|secret|password|session|cookie/i;
const SENSITIVE_CONTENT_PATTERN =
  /authorization\s*:|bearer\s+[a-z0-9._-]+|document\.cookie|password\s*[:=]/i;

export async function loadFixtureCorpus(root: string): Promise<FixtureCase[]> {
  const metadataPaths = await findMetadataFiles(root);
  const fixtures = await Promise.all(metadataPaths.map(loadFixtureCase));
  const ids = new Set<string>();
  fixtures.forEach((fixture) => {
    if (ids.has(fixture.metadata.id)) {
      throw new Error(`중복 fixture id: ${fixture.metadata.id}`);
    }
    ids.add(fixture.metadata.id);
  });
  return fixtures.sort((lhs, rhs) =>
    lhs.metadata.id.localeCompare(rhs.metadata.id));
}

async function loadFixtureCase(metadataPath: string): Promise<FixtureCase> {
  const directory = resolve(metadataPath, "..");
  const metadata = parseMetadata(await readFile(metadataPath, "utf8"));
  const expected = parseExpected(
    await readFile(join(directory, "expected.json"), "utf8"),
  );
  const inputPath = fixtureFilePath(directory, metadata.inputFile);
  const renderedPath = metadata.renderedFile === undefined ?
    null :
    fixtureFilePath(directory, metadata.renderedFile);
  const [inputHTML, renderedHTML] = await Promise.all([
    readFile(inputPath, "utf8"),
    renderedPath === null ?
      Promise.resolve(null) :
      readFile(renderedPath, "utf8"),
  ]);
  validateSensitiveData(metadata, expected, inputHTML, renderedHTML);
  return {directory, metadata, expected, inputHTML, renderedHTML};
}

async function findMetadataFiles(directory: string): Promise<string[]> {
  const entries = await readdir(directory, {withFileTypes: true});
  const nested = await Promise.all(entries.map(async (entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      return findMetadataFiles(path);
    }
    return entry.isFile() && entry.name === "metadata.json" ? [path] : [];
  }));
  return nested.flat();
}

function parseMetadata(text: string): FixtureMetadata {
  const value = JSON.parse(text) as Partial<FixtureMetadata>;
  if (
    value.schemaVersion !== 1 ||
    typeof value.id !== "string" ||
    (value.kind !== "discovery" && value.kind !== "season_images") ||
    !["generic", "platform", "incident"].includes(value.classification ?? "") ||
    typeof value.sourceURL !== "string" ||
    typeof value.inputFile !== "string" ||
    value.provenance === undefined ||
    !["synthetic", "incident_minimized"].includes(value.provenance.kind) ||
    typeof value.provenance.issue !== "string"
  ) {
    throw new Error("fixture metadata.json 계약이 올바르지 않습니다.");
  }
  return value as FixtureMetadata;
}

function parseExpected(text: string): FixtureExpected {
  const value = JSON.parse(text) as Partial<FixtureExpected>;
  if (
    value.schemaVersion !== 1 ||
    !Array.isArray(value.candidates) ||
    !value.candidates.every(validCandidateSpec) ||
    !Array.isArray(value.negativeCandidateKeys) ||
    !value.negativeCandidateKeys.every((item) => typeof item === "string") ||
    (value.orderPolicy !== "strict" && value.orderPolicy !== "relative") ||
    typeof value.strategy !== "string" ||
    value.adapter === undefined ||
    !(value.quality === null || (
      value.quality !== undefined &&
      ["accepted", "needsReview", "failed"].includes(value.quality.status) &&
      Array.isArray(value.quality.reasons)
    ))
  ) {
    throw new Error("fixture expected.json 계약이 올바르지 않습니다.");
  }
  return value as FixtureExpected;
}

function validCandidateSpec(value: unknown): value is ExpectedCandidateSpec {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const item = value as Record<string, unknown>;
  if (item.type === "exact") {
    return typeof item.key === "string" &&
      (item.title === undefined || typeof item.title === "string");
  }
  return item.type === "numeric_range" &&
    typeof item.template === "string" &&
    item.template.includes("{index}") &&
    Number.isSafeInteger(item.start) &&
    Number.isSafeInteger(item.end) &&
    Number(item.start) > 0 &&
    Number(item.end) >= Number(item.start);
}

function fixtureFilePath(directory: string, relativePath: string): string {
  const path = resolve(directory, relativePath);
  if (!path.startsWith(`${directory}${sep}`)) {
    throw new Error(`fixture 디렉터리 밖의 파일은 읽을 수 없습니다: ${relativePath}`);
  }
  return path;
}

function validateSensitiveData(
  metadata: FixtureMetadata,
  expected: FixtureExpected,
  inputHTML: string,
  renderedHTML: string | null,
): void {
  const sourceURL = new URL(metadata.sourceURL);
  const sensitiveKey = Array.from(sourceURL.searchParams.keys())
    .find((key) => SENSITIVE_QUERY_KEY_PATTERN.test(key));
  const serialized = JSON.stringify({metadata, expected});
  if (
    sensitiveKey !== undefined ||
    SENSITIVE_CONTENT_PATTERN.test(serialized)
  ) {
    throw new Error(`fixture에 민감 URL/metadata가 포함됐습니다: ${metadata.id}`);
  }
  if (
    SENSITIVE_CONTENT_PATTERN.test(inputHTML) ||
    (renderedHTML !== null && SENSITIVE_CONTENT_PATTERN.test(renderedHTML))
  ) {
    throw new Error(`fixture HTML에 민감 데이터가 포함됐습니다: ${metadata.id}`);
  }
}
