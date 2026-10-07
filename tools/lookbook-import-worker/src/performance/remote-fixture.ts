import {Response} from "undici";
import {tinyBrandInput} from "./brand-fixture.js";
import {CORPUS_DIGEST, remotePlanDigest, type RemoteCampaign}
  from "./remote-contract.js";
import type {RemotePorts} from "./remote-io.js";

export const testCampaign = (): RemoteCampaign => ({version: 5,
  planDigest: remotePlanDigest(),
  campaignID: "remote-test-campaign", corpusDigest: CORPUS_DIGEST,
  sourceRevision: "a".repeat(40), sourceDigest: "b".repeat(64),
  expiresAtMs: Date.now() + 3600000, runTimeoutMs: 30000});

export async function remoteFixture() {
  const {input} = await tinyBrandInput();
  const bytes = await input.readImage();
  const objects = new Map<string, Buffer>();
  const documents = new Map<string, Record<string, unknown>>();
  const delays: number[] = [];
  const ports: RemotePorts = {
    fetch: async () => new Response(bytes),
    put: async (path, body) => {
      if (objects.has(path)) throw Object.assign(new Error("충돌"), {code: 412});
      objects.set(path, Buffer.from(body));
    },
    get: async (path) => {
      const bytes = objects.get(path);
      if (!bytes) throw new Error("객체 누락");
      return Buffer.from(bytes);
    },
    read: async (path) => documents.get(path),
    set: async (path, data) => {
      documents.set(path, {...documents.get(path), ...structuredClone(data)});
    },
    wait: async (ms, signal) => {
      signal.throwIfAborted(); delays.push(ms);
    },
  };
  return {input, bytes, ports, objects, documents, delays};
}
