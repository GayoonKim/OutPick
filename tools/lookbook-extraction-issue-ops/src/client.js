import {randomUUID} from "node:crypto";

export async function callIssueOperations(input, fetchImplementation = fetch) {
  const requestID = randomUUID().replaceAll("-", "");
  const response = await fetchImplementation(input.uri, {
    method: "POST",
    headers: {
      "authorization": `Bearer ${input.token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      apiVersion: 1,
      environment: input.command.environment,
      requestID,
      action: input.command.action,
      payload: input.command.payload,
    }),
  });
  const body = await response.json();
  if (!response.ok) {
    const message = body?.error?.message ?? `HTTP ${response.status}`;
    throw new Error(message);
  }
  return body;
}

export function formatResult(body, json) {
  if (json) return JSON.stringify(body, null, 2);
  const result = body.result;
  if (Array.isArray(result)) {
    return result.map(summaryLine).join("\n");
  }
  if (Array.isArray(result?.clusters)) {
    const lines = result.clusters.map(summaryLine);
    if (result.nextCursor) lines.push(`nextCursor: ${result.nextCursor}`);
    return lines.join("\n") || "issue cluster가 없습니다.";
  }
  return JSON.stringify(result, null, 2);
}

function summaryLine(value) {
  if (value?.cluster) return summaryLine(value.cluster);
  if (value?.fingerprint && value?.status && !value?.stage) {
    return `${value.fingerprint} ${value.status}`;
  }
  return [
    value?.fingerprint,
    value?.stage,
    value?.adapterScope,
    value?.adapterKey,
    value?.status,
    `occurrences=${value?.occurrenceCount ?? 0}`,
  ].filter(Boolean).join(" ");
}
