#!/usr/bin/env node
import {createWriteStream} from "node:fs";
import {readFile, writeFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const DEFAULT_ANALYSIS_INPUT = "tools/season_candidate_benchmark_analysis.csv";
const DEFAULT_JSONL_INPUT = "tools/season_candidate_benchmark.jsonl";
const DEFAULT_CSV_OUTPUT = "tools/single_candidate_detail_experiment.csv";
const DEFAULT_JSONL_OUTPUT = "tools/single_candidate_detail_experiment.jsonl";
const USER_AGENT = "ChatGPT-User; OutPick single candidate detail experiment";
const NOISE_IMAGE_PATTERN =
  /(?:logo|icon|favicon|sns|insta|instagram|facebook|kakao|youtube|global|flag|chat|blank|placeholder|loading|sprite)/i;

const args = parseArgs(process.argv.slice(2));
const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const analysisPath = resolve(rootDir, args.analysisInput ?? DEFAULT_ANALYSIS_INPUT);
const jsonlInputPath = resolve(rootDir, args.jsonlInput ?? DEFAULT_JSONL_INPUT);
const csvOutputPath = resolve(rootDir, args.csvOutput ?? DEFAULT_CSV_OUTPUT);
const jsonlOutputPath = resolve(rootDir, args.jsonlOutput ?? DEFAULT_JSONL_OUTPUT);
const concurrency = Math.max(1, positiveInteger(args.concurrency, 12));
const timeoutMs = Math.max(1000, positiveInteger(args.timeoutMs, 12000));
const imageThreshold = Math.max(1, positiveInteger(args.imageThreshold, 4));
const limit = positiveInteger(args.limit, 0);

const analysisRows = parseCSV(await readFile(analysisPath, "utf8"));
const benchmarkByBrand = await readJSONLByBrand(jsonlInputPath);
const targetRows = analysisRows
  .filter((row) => row.issueCategory === "single_candidate_review")
  .slice(0, limit > 0 ? limit : undefined);
const csvRows = [];
const jsonlStream = createWriteStream(jsonlOutputPath, {encoding: "utf8"});
let completed = 0;

console.log(
  `start targets=${targetRows.length} concurrency=${concurrency} ` +
  `threshold=${imageThreshold}`,
);

await mapLimited(targetRows, concurrency, async (row) => {
  const detail = await experimentRow(row, benchmarkByBrand, timeoutMs, imageThreshold);
  csvRows.push(csvRow(detail));
  jsonlStream.write(`${JSON.stringify(detail)}\n`);
  completed += 1;
  console.log(
    `[${completed}/${targetRows.length}] ${detail.brandId} ` +
    `${detail.result} images=${detail.detailImageCount} ${detail.seasonURL}`,
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
console.log(`done csv=${csvOutputPath} jsonl=${jsonlOutputPath}`);

async function experimentRow(row, benchmarkByBrand, requestTimeoutMs, threshold) {
  const benchmark = benchmarkByBrand.get(row.brandId) ?? {};
  const topCandidate = benchmark.topCandidate ?? {};
  const seasonURL = topCandidate.seasonURL ?? row.topSeasonUrl ?? "";
  const base = {
    rowIndex: row.rowIndex,
    brandId: row.brandId,
    brandName: row.brandName,
    englishName: row.englishName,
    officialSiteUrl: row.officialSiteUrl,
    lookbookIndexUrl: row.lookbookIndexUrl,
    seasonURL,
    seasonTitle: topCandidate.title ?? row.topTitle ?? "",
    parserScore: topCandidate.score ?? row.topScore ?? "",
  };

  try {
    const html = await fetchHTML(seasonURL, requestTimeoutMs);
    const imageURLs = extractImageURLs(html, seasonURL);
    return {
      ...base,
      result: imageURLs.length >= threshold ? "promote" : "keep_review",
      detailImageCount: imageURLs.length,
      sampleImageURLs: imageURLs.slice(0, 12),
      error: null,
    };
  } catch (error) {
    return {
      ...base,
      result: "fetch_error",
      detailImageCount: 0,
      sampleImageURLs: [],
      error: error instanceof Error ? error.message : "unknown_error",
    };
  }
}

async function fetchHTML(url, requestTimeoutMs) {
  if (!url) {
    throw new Error("missing_url");
  }
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

function extractImageURLs(html, baseURL) {
  const values = [];
  for (const tagMatch of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = tagMatch[0];
    values.push(
      attributeValue(tag, "ec-data-src"),
      attributeValue(tag, "data-src"),
      attributeValue(tag, "data-original"),
      attributeValue(tag, "data-lazy-src"),
      attributeValue(tag, "src"),
      ...srcsetURLs(attributeValue(tag, "srcset")),
      ...srcsetURLs(attributeValue(tag, "data-srcset")),
    );
  }
  for (const metaMatch of html.matchAll(/<meta\b[^>]*>/gi)) {
    const tag = metaMatch[0];
    const property = attributeValue(tag, "property") ?? attributeValue(tag, "name");
    if (property?.toLowerCase() === "og:image") {
      values.push(attributeValue(tag, "content"));
    }
  }

  const seen = new Set();
  const urls = [];
  for (const value of values) {
    const url = normalizedImageURL(value, baseURL);
    if (!url || seen.has(url) || NOISE_IMAGE_PATTERN.test(url)) {
      continue;
    }
    seen.add(url);
    urls.push(url);
  }
  return urls;
}

function normalizedImageURL(rawValue, baseURL) {
  if (!rawValue) {
    return null;
  }
  const trimmed = htmlDecode(rawValue).trim();
  if (!trimmed || trimmed.startsWith("data:")) {
    return null;
  }
  try {
    const url = new URL(trimmed, baseURL);
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return null;
    }
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function attributeValue(tag, attributeName) {
  const pattern = new RegExp(
    `${attributeName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`,
    "i",
  );
  const match = tag.match(pattern);
  const value = match?.[2] ?? match?.[3] ?? match?.[4] ?? null;
  return value ? htmlDecode(value) : null;
}

function srcsetURLs(srcset) {
  if (!srcset) {
    return [];
  }
  return srcset
    .split(",")
    .map((candidate) => candidate.trim().split(/\s+/)[0])
    .filter((candidate) => candidate.length > 0);
}

async function readJSONLByBrand(path) {
  const map = new Map();
  const text = await readFile(path, "utf8");
  for (const line of text.split(/\n/)) {
    if (!line.trim()) {
      continue;
    }
    const value = JSON.parse(line);
    map.set(value.brandId, value);
  }
  return map;
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
    "seasonURL",
    "seasonTitle",
    "parserScore",
    "result",
    "detailImageCount",
    "sampleImageURLs",
    "error",
  ];
  const lines = [
    headers.join(","),
    ...rows.map((row) => headers.map((header) => csvEscape(
      header === "sampleImageURLs" ?
        JSON.stringify(row[header] ?? []) :
        row[header],
    )).join(",")),
  ];
  return `${lines.join("\n")}\n`;
}

function csvRow(detail) {
  return {
    ...detail,
    sampleImageURLs: detail.sampleImageURLs,
  };
}

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\n\r]/.test(text)) {
    return `"${text.replace(/"/g, "\"\"")}"`;
  }
  return text;
}

function htmlDecode(value) {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ");
}

function numberValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}
