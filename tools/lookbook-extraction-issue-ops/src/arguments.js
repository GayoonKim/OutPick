const READ_COMMANDS = new Set(["list", "show", "show-batch"]);
const WRITE_ACTIONS = Object.freeze({
  start: "startProcessing",
  "needs-ground-truth": "markNeedsGroundTruth",
  "ground-truth": "recordGroundTruthAndResume",
  reopen: "reopen",
  "wont-fix": "markWontFix",
});

export function parseArguments(argv) {
  const [command, ...tokens] = argv;
  if (
    !command ||
    (!READ_COMMANDS.has(command) && !WRITE_ACTIONS[command] && command !== "verify-fix")
  ) {
    throw new Error("지원하지 않는 command입니다.");
  }
  const flags = parseFlags(tokens);
  assertAllowedFlags(flags, command);
  const environment = one(flags, "environment", true);
  if (environment !== "development" && environment !== "production") {
    throw new Error("--environment는 development 또는 production이어야 합니다.");
  }
  const json = booleanFlag(flags, "json");
  if (command === "verify-fix") {
    if (
      environment === "production" &&
      one(flags, "confirm-production", false) !== "outpick-664ae"
    ) {
      throw new Error("Production verify-fix에는 확인값이 필요합니다.");
    }
    return {
      endpoint: "release",
      environment,
      json,
      action: "verifyFix",
      payload: {
        fingerprint: one(flags, "fingerprint", true),
        expectedStateVersion: requiredInteger(flags, "expected-state-version"),
        stage: one(flags, "stage", true),
        targetRuntimeVersion: one(flags, "target-runtime-version", true),
        workerRevision: one(flags, "worker-revision", true),
        workerSourceRevision: one(flags, "worker-source-revision", true),
      },
    };
  }
  if (command === "list") {
    return {
      endpoint: "read",
      environment,
      json,
      action: "listClusters",
      payload: compact({
        limit: optionalInteger(flags, "limit"),
        statuses: many(flags, "status"),
        stage: one(flags, "stage", false),
        seenAfter: one(flags, "seen-after", false),
        recurrenceOnly: booleanFlag(flags, "recurrence-only"),
        cursor: one(flags, "cursor", false),
      }),
    };
  }
  if (command === "show") {
    return readFingerprintCommand(environment, json, "getCluster", flags);
  }
  if (command === "show-batch") {
    const fingerprints = many(flags, "fingerprint");
    if (!fingerprints || fingerprints.length < 1 || fingerprints.length > 20) {
      throw new Error("--fingerprint를 1~20개 지정해야 합니다.");
    }
    return {
      endpoint: "read",
      environment,
      json,
      action: "getClustersBatch",
      payload: {fingerprints},
    };
  }
  const payload = {
    fingerprint: one(flags, "fingerprint", true),
    expectedStateVersion: requiredInteger(flags, "expected-state-version"),
  };
  if (command === "ground-truth") {
    payload.groundTruth = compact({
      expectedCandidateCount: optionalInteger(flags, "expected-count"),
      candidateKeys: many(flags, "candidate-key") ?? [],
      sourceClassification: one(flags, "source-classification", true),
      note: one(flags, "note", false),
    });
  } else if (command === "reopen") {
    payload.reason = one(flags, "reason", true);
  } else if (command === "wont-fix") {
    payload.wontFixReason = one(flags, "reason", true);
    payload.note = one(flags, "note", true);
  }
  if (
    environment === "production" &&
    one(flags, "confirm-production", false) !== "outpick-664ae"
  ) {
    throw new Error(
      "Production write에는 --confirm-production outpick-664ae가 필요합니다.",
    );
  }
  return {
    endpoint: "write",
    environment,
    json,
    action: WRITE_ACTIONS[command],
    payload,
  };
}

function assertAllowedFlags(flags, command) {
  const common = ["environment", "json"];
  const byCommand = {
    list: [
      "limit", "status", "stage", "seen-after", "recurrence-only", "cursor",
    ],
    show: ["fingerprint"],
    "show-batch": ["fingerprint"],
    start: ["fingerprint", "expected-state-version", "confirm-production"],
    "needs-ground-truth": [
      "fingerprint", "expected-state-version", "confirm-production",
    ],
    "ground-truth": [
      "fingerprint", "expected-state-version", "expected-count",
      "candidate-key", "source-classification", "note", "confirm-production",
    ],
    reopen: [
      "fingerprint", "expected-state-version", "reason", "confirm-production",
    ],
    "wont-fix": [
      "fingerprint", "expected-state-version", "reason", "note",
      "confirm-production",
    ],
    "verify-fix": [
      "fingerprint", "expected-state-version", "stage",
      "target-runtime-version", "worker-revision", "worker-source-revision",
      "confirm-production",
    ],
  };
  const allowed = new Set([...common, ...(byCommand[command] ?? [])]);
  const unknown = Array.from(flags.keys()).find((name) => !allowed.has(name));
  if (unknown) throw new Error(`허용되지 않은 flag입니다: --${unknown}`);
}

function readFingerprintCommand(environment, json, action, flags) {
  return {
    endpoint: "read",
    environment,
    json,
    action,
    payload: {fingerprint: one(flags, "fingerprint", true)},
  };
}

function parseFlags(tokens) {
  const result = new Map();
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token?.startsWith("--")) throw new Error(`잘못된 인자입니다: ${token}`);
    const name = token.slice(2);
    if (["json", "recurrence-only"].includes(name)) {
      append(result, name, true);
      continue;
    }
    const value = tokens[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`--${name} 값이 필요합니다.`);
    }
    append(result, name, value);
    index += 1;
  }
  return result;
}

function append(map, name, value) {
  const values = map.get(name) ?? [];
  values.push(value);
  map.set(name, values);
}

function one(flags, name, required) {
  const values = flags.get(name);
  if (!values || values.length === 0) {
    if (required) throw new Error(`--${name} 값이 필요합니다.`);
    return undefined;
  }
  if (values.length !== 1 || typeof values[0] !== "string") {
    throw new Error(`--${name}는 한 번만 지정할 수 있습니다.`);
  }
  return values[0];
}

function many(flags, name) {
  const values = flags.get(name);
  if (!values) return undefined;
  if (values.some((value) => typeof value !== "string")) {
    throw new Error(`--${name} 값이 올바르지 않습니다.`);
  }
  return values;
}

function booleanFlag(flags, name) {
  const values = flags.get(name);
  if (!values) return false;
  if (values.length !== 1 || values[0] !== true) {
    throw new Error(`--${name}는 값 없는 flag입니다.`);
  }
  return true;
}

function optionalInteger(flags, name) {
  const value = one(flags, name, false);
  if (value === undefined) return undefined;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`--${name} 값이 올바르지 않습니다.`);
  }
  return parsed;
}

function requiredInteger(flags, name) {
  const value = optionalInteger(flags, name);
  if (value === undefined) throw new Error(`--${name} 값이 필요합니다.`);
  return value;
}

function compact(value) {
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  );
}
