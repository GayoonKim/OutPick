/* eslint-disable require-jsdoc, max-len */
import {createHash} from "node:crypto";
import {FieldValue} from "firebase-admin/firestore";

export const SEASON_DISCOVERY_SCHEMA_VERSION = 1;
export const SEASON_DISCOVERY_EXTRACTOR_VERSION = "season-discovery-v1";
export const SEASON_DISCOVERY_CONTRACT_REVISION = 2;
export const SEASON_DISCOVERY_LIMITS = Object.freeze({
  maxLoadMoreClicks: 20,
  maxScrollAttempts: 20,
  settleMs: 800,
  timeoutMs: 45000,
  maxDiagnosticCandidates: 120,
  maxStoredCandidates: 80,
});

export type SeasonDiscoveryFingerprintInput = {
  brandID: string;
  sourceArchiveURL: string;
  extractorVersion: string;
  extractionContractRevision: number;
  adapterKey: string | null;
  adapterVersion: string | null;
  schemaVersion: number;
  limits: Record<string, number>;
};

export function canonicalDiscoveryURL(rawValue: string): string {
  const parsed = new URL(rawValue);
  parsed.protocol = parsed.protocol.toLowerCase();
  parsed.hostname = parsed.hostname.toLowerCase();
  parsed.hash = "";
  if ((parsed.protocol === "https:" && parsed.port === "443") ||
      (parsed.protocol === "http:" && parsed.port === "80")) parsed.port = "";
  Array.from(parsed.searchParams.keys())
    .filter((key) => /^utm_|^(?:fbclid|gclid)$/i.test(key))
    .forEach((key) => parsed.searchParams.delete(key));
  parsed.searchParams.sort();
  return parsed.toString();
}

export function seasonDiscoveryRequestFingerprint(
  input: SeasonDiscoveryFingerprintInput
): string {
  const stableLimits = Object.fromEntries(
    Object.entries(input.limits).sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
  );
  const value = JSON.stringify({
    brandID: input.brandID,
    sourceArchiveURL: canonicalDiscoveryURL(input.sourceArchiveURL),
    extractorVersion: input.extractorVersion,
    extractionContractRevision: input.extractionContractRevision,
    adapterKey: input.adapterKey,
    adapterVersion: input.adapterVersion,
    schemaVersion: input.schemaVersion,
    limits: stableLimits,
  });
  return createHash("sha256").update(value).digest("hex");
}

export function initialSeasonDiscoveryJob(
  transaction: FirebaseFirestore.Transaction,
  brandRef: FirebaseFirestore.DocumentReference,
  requestedBy: string,
  sourceArchiveURL: string
): {jobID: string; generation: number; fingerprint: string} {
  const jobRef = brandRef.collection("seasonDiscoveryJobs").doc();
  const generation = 1;
  const fingerprint = seasonDiscoveryCreationFingerprint(
    brandRef.id, sourceArchiveURL
  );
  transaction.set(jobRef, {
    brandID: brandRef.id,
    generation,
    requestFingerprint: fingerprint,
    sourceArchiveURL,
    sourceArchiveURLFingerprint: fingerprint,
    schemaVersion: SEASON_DISCOVERY_SCHEMA_VERSION,
    extractorVersion: SEASON_DISCOVERY_EXTRACTOR_VERSION,
    extractionContractRevision: SEASON_DISCOVERY_CONTRACT_REVISION,
    adapterKey: null,
    adapterVersion: null,
    limits: SEASON_DISCOVERY_LIMITS,
    status: "queued",
    phase: "dispatching",
    dispatchGeneration: 0,
    attemptCount: 0,
    requestedBy,
    requestReason: "brandCreated",
    coalescedRequestCount: 0,
    recommendedAction: "none",
    resolvedByJobID: null,
    leaseOwner: null,
    leaseExpiresAt: null,
    expiresAt: null,
    createdAt: FieldValue.serverTimestamp(),
    lastRequestedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {jobID: jobRef.id, generation, fingerprint};
}

export function seasonDiscoveryCreationFingerprint(
  brandID: string,
  sourceArchiveURL: string
): string {
  return seasonDiscoveryRequestFingerprint({
    brandID,
    sourceArchiveURL,
    extractorVersion: SEASON_DISCOVERY_EXTRACTOR_VERSION,
    extractionContractRevision: SEASON_DISCOVERY_CONTRACT_REVISION,
    adapterKey: null,
    adapterVersion: null,
    schemaVersion: SEASON_DISCOVERY_SCHEMA_VERSION,
    limits: SEASON_DISCOVERY_LIMITS,
  });
}
