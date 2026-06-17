#!/usr/bin/env node
import {createWriteStream} from "node:fs";
import {readFile, writeFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const DEFAULT_BENCHMARK_JSONL = "tools/season_candidate_benchmark.jsonl";
const DEFAULT_DETAIL_CSV = "tools/single_candidate_detail_experiment.csv";
const DEFAULT_CSV_OUTPUT = "tools/season_candidate_final.csv";
const DEFAULT_JSONL_OUTPUT = "tools/season_candidate_final.jsonl";
const IMAGE_FILE_URL_PATTERN = /\.(?:avif|gif|jpe?g|png|webp)(?:$|[?#])/i;

const args = parseArgs(process.argv.slice(2));
const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const benchmarkPath = resolve(rootDir, args.benchmarkJsonl ?? DEFAULT_BENCHMARK_JSONL);
const detailPath = resolve(rootDir, args.detailCsv ?? DEFAULT_DETAIL_CSV);
const csvOutputPath = resolve(rootDir, args.csvOutput ?? DEFAULT_CSV_OUTPUT);
const jsonlOutputPath = resolve(rootDir, args.jsonlOutput ?? DEFAULT_JSONL_OUTPUT);
const detailImageThreshold = Math.max(1, positiveInteger(args.imageThreshold, 4));

const benchmarkRows = await readJSONL(benchmarkPath);
const detailByBrand = new Map(
  parseCSV(await readFile(detailPath, "utf8"))
    .filter((row) => row.result === "promote")
    .map((row) => [row.brandId, row]),
);

const brandResults = [];
const csvRows = [];

for (const benchmark of benchmarkRows) {
  const acceptedCandidates = acceptedCandidatesForBrand(
    benchmark,
    detailByBrand.get(benchmark.brandId),
    detailImageThreshold,
  );
  if (acceptedCandidates.length === 0) {
    continue;
  }

  brandResults.push({
    rowIndex: benchmark.rowIndex,
    brandId: benchmark.brandId,
    brandName: benchmark.brandName,
    englishName: benchmark.englishName,
    officialSiteUrl: benchmark.officialSiteUrl,
    lookbookIndexUrl: benchmark.lookbookIndexUrl,
    sourceStatus: acceptedCandidates[0].sourceStatus,
    candidateCount: acceptedCandidates.length,
    candidates: acceptedCandidates.map((candidate) => ({
      title: candidate.title,
      seasonURL: candidate.seasonURL,
      coverImageURL: candidate.coverImageURL,
      score: candidate.score,
      sourceStatus: candidate.sourceStatus,
      detailImageCount: candidate.detailImageCount,
    })),
  });

  acceptedCandidates.forEach((candidate, index) => {
    csvRows.push({
      rowIndex: benchmark.rowIndex,
      brandId: benchmark.brandId,
      brandName: benchmark.brandName,
      englishName: benchmark.englishName,
      officialSiteUrl: benchmark.officialSiteUrl,
      lookbookIndexUrl: benchmark.lookbookIndexUrl,
      sourceStatus: candidate.sourceStatus,
      candidateRank: index + 1,
      candidateCount: acceptedCandidates.length,
      seasonTitle: candidate.title,
      seasonURL: candidate.seasonURL,
      coverImageURL: candidate.coverImageURL ?? "",
      score: candidate.score,
      detailImageCount: candidate.detailImageCount ?? "",
    });
  });
}

brandResults.sort((lhs, rhs) => numberValue(lhs.rowIndex) - numberValue(rhs.rowIndex));
csvRows.sort((lhs, rhs) => {
  if (numberValue(lhs.rowIndex) !== numberValue(rhs.rowIndex)) {
    return numberValue(lhs.rowIndex) - numberValue(rhs.rowIndex);
  }
  return numberValue(lhs.candidateRank) - numberValue(rhs.candidateRank);
});

await writeFile(csvOutputPath, toCSV(csvRows), "utf8");
await writeJSONL(jsonlOutputPath, brandResults);

const summary = csvRows.reduce(
  (acc, row) => {
    acc[row.sourceStatus] = (acc[row.sourceStatus] ?? 0) + 1;
    return acc;
  },
  {},
);
console.log(
  `done brands=${brandResults.length} candidates=${csvRows.length} ` +
  `${JSON.stringify(summary)} csv=${csvOutputPath} jsonl=${jsonlOutputPath}`,
);

function acceptedCandidatesForBrand(benchmark, detailRow, threshold) {
  if (benchmark.status === "success") {
    return (benchmark.candidates ?? [])
      .filter((candidate) => !isImageFileURL(candidate.seasonURL))
      .map((candidate) => ({
        ...candidate,
        sourceStatus: "parser_success",
        detailImageCount: null,
      }));
  }

  if (!detailRow || numberValue(detailRow.detailImageCount) < threshold) {
    return [];
  }

  const topCandidate = benchmark.topCandidate;
  if (!topCandidate || isImageFileURL(topCandidate.seasonURL)) {
    return [];
  }

  return [{
    ...topCandidate,
    sourceStatus: "single_candidate_detail_promote",
    detailImageCount: numberValue(detailRow.detailImageCount),
  }];
}

function isImageFileURL(value) {
  if (!value) {
    return false;
  }
  try {
    return IMAGE_FILE_URL_PATTERN.test(new URL(value).pathname);
  } catch {
    return IMAGE_FILE_URL_PATTERN.test(String(value));
  }
}

async function readJSONL(path) {
  const rows = [];
  const text = await readFile(path, "utf8");
  for (const line of text.split(/\n/)) {
    if (line.trim()) {
      rows.push(JSON.parse(line));
    }
  }
  return rows;
}

async function writeJSONL(path, rows) {
  const stream = createWriteStream(path, {encoding: "utf8"});
  for (const row of rows) {
    stream.write(`${JSON.stringify(row)}\n`);
  }
  await new Promise((resolveStream, rejectStream) => {
    stream.end((error) => {
      if (error) {
        rejectStream(error);
        return;
      }
      resolveStream();
    });
  });
}

function parseCSV(text) {
  const normalized = text.replace(/^\uFEFF/, "");
  const rows = [];
  let row = [];
  let value = "";
  let inQuotes = false;

  for (let index = 0; index < normalized.length; index += 1) {
    const char = normalized[index];
    const next = normalized[index + 1];
    if (inQuotes) {
      if (char === "\"" && next === "\"") {
        value += "\"";
        index += 1;
      } else if (char === "\"") {
        inQuotes = false;
      } else {
        value += char;
      }
      continue;
    }

    if (char === "\"") {
      inQuotes = true;
    } else if (char === ",") {
      row.push(value);
      value = "";
    } else if (char === "\n") {
      row.push(value);
      rows.push(row);
      row = [];
      value = "";
    } else if (char !== "\r") {
      value += char;
    }
  }
  if (value.length > 0 || row.length > 0) {
    row.push(value);
    rows.push(row);
  }

  const headers = rows.shift() ?? [];
  return rows
    .filter((values) => values.some((item) => item.length > 0))
    .map((values) => Object.fromEntries(
      headers.map((header, index) => [header, values[index] ?? ""]),
    ));
}

function toCSV(rows) {
  const headers = [
    "rowIndex",
    "brandId",
    "brandName",
    "englishName",
    "officialSiteUrl",
    "lookbookIndexUrl",
    "sourceStatus",
    "candidateRank",
    "candidateCount",
    "seasonTitle",
    "seasonURL",
    "coverImageURL",
    "score",
    "detailImageCount",
  ];
  const lines = [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => {
      return csvEscape(row[header]);
    }).join(",")),
  ];
  return `${lines.join("\n")}\n`;
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, "\"\"")}"`;
  }
  return text;
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      continue;
    }
    const key = arg.slice(2).replace(/-([a-z])/g, (_, char) => char.toUpperCase());
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      parsed[key] = "true";
    } else {
      parsed[key] = next;
      index += 1;
    }
  }
  return parsed;
}

function positiveInteger(value, defaultValue) {
  if (value === undefined) {
    return defaultValue;
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`양의 정수 옵션이 필요합니다: ${value}`);
  }
  return parsed;
}

function numberValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}
