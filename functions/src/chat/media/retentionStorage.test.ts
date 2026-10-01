/* eslint-disable require-jsdoc */
import assert from "node:assert/strict";
import test from "node:test";
import type {Storage} from "firebase-admin/storage";
import {chatMediaRetentionStorage} from "./retentionStorage.js";

const object = {
  bucket: "chat-ready",
  path: "rooms/room-1/messages/message-1/attachments/attachment-1/display",
  generation: "1740000000000000",
  role: "original" as const,
};

function cloudStorage(
  input: {
    exactMetadata?: () => Promise<[Record<string, unknown>]>;
    currentMetadata?: () => Promise<[Record<string, unknown>]>;
    delete?: () => Promise<void>;
  } = {},
) {
  const fileCalls: Array<{
    path: string;
    options?: Record<string, unknown>;
  }> = [];
  const exact = {
    getMetadata: input.exactMetadata ?? (async () => [
      {generation: object.generation},
    ]),
    delete: input.delete ?? (async () => undefined),
  };
  const current = {
    getMetadata: input.currentMetadata ?? (async () => {
      throw Object.assign(new Error("not found"), {code: 404});
    }),
  };
  const storage = {
    bucket: (name: string) => ({
      file: (path: string, options?: Record<string, unknown>) => {
        fileCalls.push({path: `${name}/${path}`, options});
        return options?.generation ? exact : current;
      },
    }),
  } as unknown as Storage;
  return {storage, fileCalls};
}

test("GCS adapter는 경로 전체가 아닌 지정 generation에 조건부 삭제한다", async () => {
  const fake = cloudStorage();
  await chatMediaRetentionStorage(fake.storage).deleteExactGeneration(object);
  assert.equal(fake.fileCalls.length, 1);
  assert.equal(fake.fileCalls[0]?.path, `${object.bucket}/${object.path}`);
  assert.deepEqual(fake.fileCalls[0]?.options, {
    generation: object.generation,
    preconditionOpts: {ifGenerationMatch: object.generation},
  });
});

test("정확한 generation과 현재 경로가 모두 없으면 이미 삭제된 것으로 수렴한다", async () => {
  const fake = cloudStorage({
    exactMetadata: async () => {
      throw Object.assign(new Error("not found"), {code: 404});
    },
  });
  await chatMediaRetentionStorage(fake.storage).deleteExactGeneration(object);
  assert.equal(fake.fileCalls.length, 2);
});

test("같은 경로에 다른 generation이 생겼으면 기존 객체 삭제 성공으로 취급하지 않는다", async () => {
  const fake = cloudStorage({
    exactMetadata: async () => {
      throw Object.assign(new Error("not found"), {code: 404});
    },
    currentMetadata: async () => [{generation: "1740000000000001"}],
  });
  await assert.rejects(
    chatMediaRetentionStorage(fake.storage).deleteExactGeneration(object),
    (error: unknown) => error !== null && typeof error === "object" &&
      "code" in error && (error as {code?: unknown}).code === 412,
  );
});

test("delete 응답의 404는 현재 generation이 없는 경우에만 완료로 처리한다", async () => {
  const fake = cloudStorage({
    delete: async () => {
      throw Object.assign(new Error("not found"), {code: 404});
    },
  });
  await chatMediaRetentionStorage(fake.storage).deleteExactGeneration(object);
  assert.equal(fake.fileCalls.length, 2);
});
