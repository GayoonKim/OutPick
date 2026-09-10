/* eslint-disable require-jsdoc, max-len */
import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp, type Firestore} from "firebase-admin/firestore";
import type {Request, Response} from "express";

test("이미지 dispatcher는 완료 transaction이 끝나기 전 HTTP 응답을 보내지 않는다", async () => {
  process.env.GCLOUD_PROJECT = "outpick-test";
  const {createMediaDispatcherHandler} = await import("./functions.js");
  const uploadPath = "Rooms/room/MediaUploads/upload";
  const values = new Map<string, Record<string, unknown>>([[uploadPath, {
    contractVersion: 2, kind: "images", processingStatus: "queued", processingAttempt: 0,
    processingDeadlineAt: Timestamp.fromMillis(100_000),
  }]]);
  const ref = (path: string) => ({path});
  const firestore = {doc: ref, collection: (path: string) => ({doc: (id: string) => ref(`${path}/${id}`)}),
    runTransaction: async (operation: (transaction: unknown) => Promise<unknown>) => operation({
      get: async (reference: {path: string}) => ({exists: values.has(reference.path), data: () => values.get(reference.path)}),
      set: (reference: {path: string}, data: Record<string, unknown>) => values.set(reference.path, data),
      update: (reference: {path: string}, data: Record<string, unknown>) => values.set(reference.path, {...values.get(reference.path), ...data}),
    }),
  } as unknown as Firestore;
  let release!: () => void;
  let entered!: () => void;
  const gate = new Promise<void>((resolve) => {
    release = resolve;
  });
  const entering = new Promise<void>((resolve) => {
    entered = resolve;
  });
  const order: string[] = [];
  const handler = createMediaDispatcherHandler({firestore, nowMillis: () => 1_000, projectID: () => "outpick-test",
    startExecution: async () => {
      order.push("worker_completed");
      return "service/execution";
    },
    completeImageExecution: async () => {
      entered();
      await gate;
      order.push("slot_released");
    },
  });
  let status: number | undefined;
  const response = {status: (value: number) => {
    status = value;
    return response;
  },
  json: () => {
    order.push("response");
  }} as unknown as Response;
  const request = {method: "POST", get: () => "application/json", headers: {"content-type": "application/json"},
    body: {uploadPath, kind: "images"}} as unknown as Request;
  const running = handler(request, response);
  await entering;
  assert.equal(status, undefined);
  assert.deepEqual(order, ["worker_completed"]);
  release();
  await running;
  assert.equal(status, 200);
  assert.deepEqual(order, ["worker_completed", "slot_released", "response"]);
});
