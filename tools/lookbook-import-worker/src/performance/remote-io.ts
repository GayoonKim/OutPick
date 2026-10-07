import assert from "node:assert/strict";
import {setTimeout as wait} from "node:timers/promises";
import {fetchPublicHTTP, responseBytes, retryableStatusError}
  from "../public-http.js";
import {isRetryableImportError} from "../import-error.js";
import type {ComparisonSeason} from "./comparison.js";
import type {ConnectedImage, ConnectedInput, ConnectedIO,
  ConnectedTarget} from "./reuse-input.js";
import {measured, recordBytes} from "./metrics.js";
import {sha256, assertRemoteRoots} from "./remote-contract.js";

export type RemotePorts = {
  fetch: typeof fetchPublicHTTP;
  put: (path: string, bytes: Buffer) => Promise<void>;
  get: (path: string) => Promise<Buffer>;
  read: (path: string) => Promise<Record<string, unknown> | undefined>;
  set: (path: string, data: Record<string, unknown>) => Promise<void>;
  wait?: (ms: number, signal: AbortSignal) => Promise<void>;
};
export function retryableRemote(error: unknown): boolean {
  const code = (error as {code?: unknown})?.code;
  return isRetryableImportError(error) ||
    [4, 8, 10, 13, 14, 408, 429, 500, 502, 503, 504,
      "ETIMEDOUT", "ECONNRESET"].includes(code as number);
}

// 신호를 무시하는 SDK 요청은 Promise가 끝날 때까지 기다린다.
export class RemoteIO implements ConnectedIO {
  readonly counts = {imageGET: 0, receivedBytes: 0, uploadCalls: 0,
    uploadedBytes: 0, objectReads: 0, objectReadBytes: 0,
    documentReads: 0, documentWrites: 0};
  readonly expected = new Map<string, {sha256: string; bytes: number}>();
  readonly submitted = new Map<string, {sha256: string; bytes: number}>();
  readonly saved = new Map<string, {thumbPath: string; detailPath: string}>();
  private readonly downloadErrors = new Map<string, unknown>();

  constructor(private readonly input: ConnectedInput,
    private readonly root: string, private readonly documents: string,
    private readonly ports: RemotePorts) {
    assertRemoteRoots(root, documents);
  }

  clearDownloadError(seasonID: string) {
    this.downloadErrors.delete(seasonID);
  }
  downloadError(seasonID: string) {
    return this.downloadErrors.get(seasonID);
  }
  async readImage(image: ConnectedImage, signal: AbortSignal): Promise<Buffer> {
    const season = this.input.seasons.find((s) =>
      s.seasonID === image.seasonID);
    const cover = this.input.covers.find((s) => s.seasonID === image.seasonID);
    assert.ok(season && cover);
    const known = [...season.images, cover].find((s) =>
      s.sourceURL === image.sourceURL && s.sha256 === image.sha256 &&
      s.bytes === image.bytes);
    assert.ok(known, "고정 입력 밖 이미지입니다.");
    try {
      for (let attempt = 1; ; attempt++) {
        signal.throwIfAborted();
        try {
          this.counts.imageGET++;
          const response = await this.ports.fetch(image.sourceURL, {
            signal: AbortSignal.any([signal, AbortSignal.timeout(20000)]),
            headers: {"user-agent": "OutPickLookbookImporter/0.1",
              "referer": season.sourceURL},
          });
          if (!response.ok) {
            await response.body?.cancel();
            throw retryableStatusError(response.status, "원격 이미지 GET 실패");
          }
          const bytes = await responseBytes(response, 25 * 2**20, "이미지",
            (count) => {
              this.counts.receivedBytes += count;
            });
          signal.throwIfAborted();
          assert.equal(bytes.length, image.bytes, "원본 크기 변경");
          assert.equal(sha256(bytes), image.sha256, "원본 해시 변경");
          return bytes;
        } catch (error) {
          if (signal.aborted || attempt === 3 || !retryableRemote(error)) {
            throw error;
          }
          if (this.ports.wait) await this.ports.wait(400 * attempt, signal);
          else await wait(400 * attempt, undefined, {signal});
        }
      }
    } catch (error) {
      // 해시 dedupe가 오류를 요약해도 실제 오류 분류를 잃지 않는다.
      const previous = this.downloadErrors.get(image.seasonID);
      if (!previous || retryableRemote(previous)) {
        this.downloadErrors.set(image.seasonID, error);
      }
      throw error;
    }
  }

  private location(item: ComparisonSeason, index: number,
    target: ConnectedTarget) {
    assert.equal(item.id, item.seasonID);
    const season = this.input.seasons.find((s) => s.seasonID === item.id);
    const cover = this.input.covers.find((s) => s.seasonID === item.id);
    assert.ok(season && cover);
    const seen = new Set<string>();
    const unique = season.images.filter((image) => {
      if (seen.has(image.sha256)) return false;
      seen.add(image.sha256); return true;
    });
    const expected = [...unique, cover][index];
    assert.ok(expected && expected.sha256 === target.sha256 &&
      expected.sourceURL === target.sourceURL);
    assert.equal(target.kind, index === unique.length ? "cover" : "post");
    const key = `${item.id}-${index}`;
    return {document: `${this.documents}/assets/${key}`,
      thumbPath: `${this.root}${key}/thumb.jpg`,
      detailPath: `${this.root}${key}/detail.jpg`};
  }

  async prepare(items: ComparisonSeason[], signal: AbortSignal) {
    for (const item of items) {
      const season = this.input.seasons.find((s) => s.seasonID === item.id)!;
      const count = new Set(season.images.map((s) => s.sha256)).size;
      for (let index = 0; index <= count; index++) {
        signal.throwIfAborted();
        this.counts.documentWrites++;
        await this.ports.set(`${this.documents}/assets/${item.id}-${index}`,
          index === count ? {coverPath: null} :
            {media: [{thumbPath: null, detailPath: null}]});
      }
    }
  }

  async upload(item: ComparisonSeason, index: number,
    target: ConnectedTarget, variant: "thumb" | "detail", bytes: Buffer,
    signal: AbortSignal) {
    signal.throwIfAborted();
    const location = this.location(item, index, target);
    const path = variant === "thumb" ?
      location.thumbPath : location.detailPath;
    await measured("file.upload", async () => {
      this.counts.uploadCalls++;
      this.submitted.set(path, {sha256: sha256(bytes), bytes: bytes.length});
      recordBytes("file.upload", "submittedBytes", bytes.length);
      try {
        await this.ports.put(path, bytes);
        this.counts.uploadedBytes += bytes.length;
      } catch (error) {
        if (Number((error as {code?: unknown})?.code) !== 412) throw error;
        // 재시도/응답 유실 때 기존 객체의 실제 내용을 대조한다.
        const stored = await this.readObject(path);
        assert.equal(sha256(stored), sha256(bytes));
        assert.equal(stored.length, bytes.length);
      }
      this.expected.set(path, {sha256: sha256(bytes), bytes: bytes.length});
      recordBytes("file.upload", "completedBytes", bytes.length);
      signal.throwIfAborted();
    });
  }

  async savePaths(item: ComparisonSeason, index: number,
    target: ConnectedTarget, signal: AbortSignal) {
    signal.throwIfAborted();
    const {document, thumbPath, detailPath} =
      this.location(item, index, target);
    assert.ok(this.expected.has(thumbPath) && this.expected.has(detailPath));
    let patch: Record<string, unknown>;
    if (target.kind === "cover") patch = {coverPath: detailPath};
    else {
      this.counts.documentReads++;
      const data = await this.ports.read(document);
      assert.ok(Array.isArray(data?.media) && data.media.length === 1);
      patch = {media: [{...data.media[0], thumbPath, detailPath}],
        assetSyncStatus: "ready", assetSyncErrorMessage: null};
    }
    signal.throwIfAborted();
    this.counts.documentWrites++;
    await this.ports.set(document, patch);
    this.saved.set(document, {thumbPath, detailPath});
    signal.throwIfAborted();
  }

  private async readObject(path: string) {
    this.counts.objectReads++;
    const bytes = await this.ports.get(path);
    this.counts.objectReadBytes += bytes.length;
    return bytes;
  }

  async verify(signal: AbortSignal, expectedFiles: number) {
    assert.equal(this.expected.size, expectedFiles);
    assert.equal(this.saved.size * 2, expectedFiles);
    for (const [path, expected] of this.expected) {
      signal.throwIfAborted();
      const bytes = await this.readObject(path);
      assert.deepEqual({sha256: sha256(bytes), bytes: bytes.length}, expected);
    }
    for (const [path, expected] of this.saved) {
      signal.throwIfAborted();
      this.counts.documentReads++;
      const data = await this.ports.read(path);
      if (Array.isArray(data?.media)) {
        assert.deepEqual({thumbPath: data.media[0].thumbPath,
          detailPath: data.media[0].detailPath}, expected);
      } else assert.equal(data?.coverPath, expected.detailPath);
    }
    signal.throwIfAborted();
  }
}
