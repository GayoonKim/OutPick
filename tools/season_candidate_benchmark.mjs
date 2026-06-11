#!/usr/bin/env node
import {createWriteStream} from "node:fs";
import {readFile, writeFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

const DEFAULT_INPUT = "tools/lookbook_url_success.csv";
const DEFAULT_CSV_OUTPUT = "tools/season_candidate_benchmark.csv";
const DEFAULT_JSONL_OUTPUT = "tools/season_candidate_benchmark.jsonl";
const DEFAULT_PARSER_PATH = "functions/lib/lookbookSeasonCandidateParser.js";
const USER_AGENT = "ChatGPT-User; OutPick season candidate benchmark";

const args = parseArgs(process.argv.slice(2));
const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const inputPath = resolve(rootDir, args.input ?? DEFAULT_INPUT);
const csvOutputPath = resolve(rootDir, args.csvOutput ?? DEFAULT_CSV_OUTPUT);
const jsonlOutputPath = resolve(rootDir, args.jsonlOutput ?? DEFAULT_JSONL_OUTPUT);
const parserPath = resolve(rootDir, args.parser ?? DEFAULT_PARSER_PATH);
const limit = positiveInteger(args.limit, 0);
const offset = positiveInteger(args.offset, 0);
const concurrency = Math.max(1, positiveInteger(args.concurrency, 12));
const timeoutMs = Math.max(1000, positiveInteger(args.timeoutMs, 15000));
const shardCount = Math.max(1, positiveInteger(args.shardCount, 1));
const shardIndex = positiveInteger(args.shardIndex, 0);

if (shardIndex >= shardCount) {
  throw new Error("--shard-index는 --shard-count보다 작아야 합니다.");
}

const {extractSeasonCandidates} = await import(pathToFileURL(parserPath).href);
const rows = parseCSV(await readFile(inputPath, "utf8"));
const targetRows = rows
  .slice(offset)
  .filter((_, index) => index % shardCount === shardIndex)
  .slice(0, limit > 0 ? limit : undefined);

const csvRows = [];
const jsonlStream = createWriteStream(jsonlOutputPath, {encoding: "utf8"});
let completed = 0;

console.log(
  `start targets=${targetRows.length} concurrency=${concurrency} ` +
  `shard=${shardIndex}/${shardCount}`,
);

await mapLimited(targetRows, concurrency, async (row) => {
  const result = await benchmarkRow(row, timeoutMs, extractSeasonCandidates);
  csvRows.push(csvSummaryRow(result));
  jsonlStream.write(`${JSON.stringify(result)}\n`);
  completed += 1;
  console.log(
    `[${completed}/${targetRows.length}] ${result.brandId} ` +
    `${result.status} candidates=${result.candidateCount} covers=${result.withCoverCount}`,
  );
});

await new Promise((resolveStream, rejectStream) => {
  jsonlStream.end((error) => {
    if (error) {
      rejectStream(error);
      return;
    }
    resolveStream();
  });
});

csvRows.sort((lhs, rhs) => numberValue(lhs.rowIndex) - numberValue(rhs.rowIndex));
await writeFile(csvOutputPath, toCSV(csvRows), "utf8");

const summary = csvRows.reduce(
  (acc, row) => {
    acc[row.status] = (acc[row.status] ?? 0) + 1;
    return acc;
  },
  {},
);
console.log(`done ${JSON.stringify(summary)} csv=${csvOutputPath} jsonl=${jsonlOutputPath}`);

async function benchmarkRow(row, requestTimeoutMs, parser) {
  const brandId = row.brandId ?? "";
  const lookbookIndexUrl = row.lookbookIndexUrl ?? "";
  const base = {
    rowIndex: row.rowIndex ?? "",
    brandId,
    brandName: row.brandName ?? "",
    englishName: row.englishName ?? "",
    officialSiteUrl: row.officialSiteUrl ?? "",
    lookbookIndexUrl,
  };

  if (!lookbookIndexUrl) {
    return {
      ...base,
      status: "failed",
      candidateCount: 0,
      withCoverCount: 0,
      topCandidate: null,
      candidates: [],
      error: "missing_lookbook_index_url",
    };
  }

  try {
    const html = await fetchHTML(lookbookIndexUrl, requestTimeoutMs);
    const candidates = parser(html, lookbookIndexUrl);
    const inScopeCandidates = candidates.filter((candidate) => {
      return sameSite(lookbookIndexUrl, candidate.seasonURL);
    });
    const withCoverCount = candidates.filter((candidate) => {
      return candidate.coverImageURL !== null;
    }).length;
    const inScopeWithCoverCount = inScopeCandidates.filter((candidate) => {
      return candidate.coverImageURL !== null;
    }).length;
    const topCandidate = bestCandidate(inScopeCandidates) ?? bestCandidate(candidates);
    return {
      ...base,
      status: benchmarkStatus(
        inScopeCandidates.length,
        inScopeWithCoverCount,
        topCandidate?.score ?? 0,
      ),
      candidateCount: candidates.length,
      withCoverCount,
      inScopeCandidateCount: inScopeCandidates.length,
      inScopeWithCoverCount,
      topCandidate: topCandidate ?? null,
      candidates,
      error: null,
    };
  } catch (error) {
    return {
      ...base,
      status: "failed",
      candidateCount: 0,
      withCoverCount: 0,
      inScopeCandidateCount: 0,
      inScopeWithCoverCount: 0,
      topCandidate: null,
      candidates: [],
      error: error instanceof Error ? error.message : "unknown_error",
    };
  }
}

async function fetchHTML(url, requestTimeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        "user-agent": USER_AGENT,
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.toLowerCase().includes("text/html")) {
      throw new Error(`not_html:${contentType || "unknown"}`);
    }
    return await response.text();
  } finally {
    clearTimeout(timeout);
  }
}

function benchmarkStatus(inScopeCandidateCount, inScopeWithCoverCount, topScore) {
  if (inScopeCandidateCount >= 2 && inScopeWithCoverCount >= 2 && topScore >= 100) {
    return "success";
  }
  if (inScopeCandidateCount > 0 || topScore > 0) {
    return "review";
  }
  return "failed";
}

function csvSummaryRow(result) {
  const top = result.topCandidate ?? {};
  return {
    rowIndex: result.rowIndex,
    brandId: result.brandId,
    brandName: result.brandName,
    englishName: result.englishName,
    officialSiteUrl: result.officialSiteUrl,
    lookbookIndexUrl: result.lookbookIndexUrl,
    status: result.status,
    candidateCount: result.candidateCount,
    withCoverCount: result.withCoverCount,
    inScopeCandidateCount: result.inScopeCandidateCount,
    inScopeWithCoverCount: result.inScopeWithCoverCount,
    topTitle: top.title ?? "",
    topSeasonUrl: top.seasonURL ?? "",
    topCoverImageUrl: top.coverImageURL ?? "",
    topScore: top.score ?? "",
    error: result.error ?? "",
  };
}

async function mapLimited(items, workerCount, callback) {
  let nextIndex = 0;
  const workers = Array.from({length: Math.min(workerCount, items.length)}, async () => {
    while (nextIndex < items.length) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      await callback(items[currentIndex], currentIndex);
    }
  });
  await Promise.all(workers);
}

function bestCandidate(candidates) {
  return [...candidates].sort((lhs, rhs) => {
    if (rhs.score !== lhs.score) {
      return rhs.score - lhs.score;
    }
    return lhs.seasonURL.localeCompare(rhs.seasonURL);
  })[0] ?? null;
}

function sameSite(baseURL, candidateURL) {
  try {
    const baseHost = new URL(baseURL).hostname.toLowerCase().replace(/^www\./, "");
    const candidateHost = new URL(candidateURL).hostname.toLowerCase().replace(/^www\./, "");
    return candidateHost === baseHost || candidateHost.endsWith(`.${baseHost}`);
  } catch {
    return false;
  }
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
    "status",
    "candidateCount",
    "withCoverCount",
    "inScopeCandidateCount",
    "inScopeWithCoverCount",
    "topTitle",
    "topSeasonUrl",
    "topCoverImageUrl",
    "topScore",
    "error",
  ];
  const lines = [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(row[header])).join(",")),
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

function numberValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}
