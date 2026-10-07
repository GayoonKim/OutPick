import assert from "node:assert/strict";
import type {Firestore} from "firebase-admin/firestore";
import {remotePlans, remoteRunKey, outputRoot, sha256, type RemoteCampaign,
  type RemotePlan} from "./remote-contract.js";

export const REMOTE_CONTROL = "lookbookImportPerformanceControl/active";
// 만료 자동 인계는 하지 않는다. 종료 미확인 때 다음 실험을 차단한다.
export class RemoteRunStore {
  constructor(private readonly db: Firestore) {}

  async claim(campaign: RemoteCampaign, plan: RemotePlan, owner: string,
    now = Date.now()) {
    const key = remoteRunKey(campaign, plan);
    assert.ok(owner.length > 0 && now < campaign.expiresAtMs);
    const control = this.db.doc(REMOTE_CONTROL);
    const state = this.db.doc(
      `lookbookImportPerformanceCampaigns/${campaign.campaignID}`);
    const run = this.db.doc(`lookbookImportPerformanceRuns/${key}`);
    await this.db.runTransaction(async (tx) => {
      const [lock, previous, current] = await tx.getAll(control, state, run);
      assert.ok(!current.exists, "사용한 회차는 다시 실행할 수 없습니다.");
      assert.ok(!lock.data()?.activeRun, "이전 회차 종료가 확인되지 않았습니다.");
      const data = previous.data();
      if (data) {
        assert.equal(data.digest, sha256(JSON.stringify(campaign)));
        assert.equal(data.halted, false);
        assert.ok(now - data.startedAtMs < 2 * 60 * 60 * 1000);
      }
      const next = data?.next ?? 0;
      assert.equal(remotePlans()[next]?.id, plan.id, "고정 순서 위반");
      tx.set(control, {activeRun: key, owner, startedAtMs: now});
      tx.set(state, {digest: sha256(JSON.stringify(campaign)), next,
        startedAtMs: data?.startedAtMs ?? now, halted: false});
      tx.create(run, {campaignID: campaign.campaignID, plan, owner,
        status: "running", startedAtMs: now});
    }, {maxAttempts: 5});
    return key;
  }

  async finish(campaign: RemoteCampaign, plan: RemotePlan, owner: string,
    result: {status: string; evidencePath: string; continueAllowed: boolean}) {
    assert.equal(result.evidencePath,
      `${outputRoot(campaign, plan)}result.json`);
    const key = remoteRunKey(campaign, plan);
    const control = this.db.doc(REMOTE_CONTROL);
    const state = this.db.doc(
      `lookbookImportPerformanceCampaigns/${campaign.campaignID}`);
    const run = this.db.doc(`lookbookImportPerformanceRuns/${key}`);
    await this.db.runTransaction(async (tx) => {
      const [lock, previous, current] = await tx.getAll(control, state, run);
      assert.equal(previous.data()?.digest, sha256(JSON.stringify(campaign)));
      assert.equal(lock.data()?.activeRun, key);
      assert.equal(lock.data()?.owner, owner);
      assert.equal(current.data()?.owner, owner);
      assert.equal(current.data()?.status, "running");
      assert.ok(!result.continueAllowed || result.status === "succeeded");
      assert.equal(remotePlans()[previous.data()?.next]?.id, plan.id);
      tx.update(run, {...result, endedAtMs: Date.now(), drained: true});
      tx.update(state, {next: previous.data()!.next + 1,
        halted: !result.continueAllowed});
      tx.set(control, {activeRun: result.continueAllowed ? null : key,
        owner: result.continueAllowed ? null : owner,
        halted: !result.continueAllowed});
    }, {maxAttempts: 5});
  }
}
