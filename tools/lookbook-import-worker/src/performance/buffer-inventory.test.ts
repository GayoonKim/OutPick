import assert from "node:assert/strict";
import test from "node:test";
import {setImmediate} from "node:timers/promises";
import {BufferInventory, observeBuffer} from "./buffer-inventory.js";
import {storeImageVariants} from "../pipeline/asset-pipeline.js";

test("바이트 관측은 같은 객체의 다중 소비를 중복 합산하지 않는다", () => {
  const inventory = new BufferInventory();
  const bytes = Buffer.alloc(10);
  const first = inventory.retain("source", bytes);
  const second = inventory.retain("source", bytes);
  assert.equal(inventory.snapshot().currentBytes, 10);
  assert.equal(inventory.snapshot().source.references, 2);
  first();
  first();
  assert.equal(inventory.snapshot().currentBytes, 10);
  second();
  assert.equal(inventory.snapshot().currentBytes, 0);
  assert.equal(inventory.snapshot().peakBytes, 10);
});

test("바이트 관측은 병렬 실행 scope를 분리하고 미설정 경로를 허용한다",
  async () => {
    observeBuffer("source", Buffer.alloc(1))();
    const inventories = [new BufferInventory(), new BufferInventory()];
    await Promise.all(inventories.map((inventory, index) =>
      inventory.run(async () => {
        const release = observeBuffer("source", Buffer.alloc(index + 1));
        await setImmediate();
        assert.equal(inventory.snapshot().currentBytes, index + 1);
        release();
      })));
    assert.ok(inventories.every((value) => value.snapshot().objects === 0));
  });

test("기준선 조기 변환 실패도 늦은 형제의 입력을 종료 전 해제하지 않는다",
  async () => {
    const inventory = new BufferInventory();
    let release!: () => void;
    const pending = new Promise<void>((resolve) => {
      release = resolve;
    });
    const work = inventory.run(() => storeImageVariants(Buffer.alloc(10),
      undefined, {
        transform: async (_bytes, variant) => {
          if (variant === "thumb") throw new Error("변환 실패");
          await pending;
          return Buffer.alloc(5);
        },
        upload: async () => assert.fail("업로드 불가"),
        savePaths: async () => assert.fail("저장 불가"),
      }));
    await assert.rejects(work);
    assert.equal(inventory.snapshot().currentBytes, 10);
    release();
    await setImmediate();
    assert.equal(inventory.snapshot().objects, 0);
  });

test("기준선 조기 업로드 실패는 실행 중 JPEG만 종료까지 보유한다",
  async () => {
    const inventory = new BufferInventory();
    let release!: () => void;
    const pending = new Promise<void>((resolve) => {
      release = resolve;
    });
    const work = inventory.run(() => storeImageVariants(Buffer.alloc(10),
      undefined, {
        transform: async (_bytes, variant) =>
          Buffer.alloc(variant === "thumb" ? 3 : 7),
        upload: async (_bytes, variant) => {
          if (variant === "thumb") throw new Error("업로드 실패");
          await pending;
        },
        savePaths: async () => assert.fail("저장 불가"),
      }));
    await assert.rejects(work);
    assert.equal(inventory.snapshot().currentBytes, 7);
    assert.equal(inventory.snapshot().source.bytes, 0);
    release();
    await setImmediate();
    assert.equal(inventory.snapshot().objects, 0);
  });
