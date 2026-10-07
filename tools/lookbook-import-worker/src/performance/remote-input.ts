import assert from "node:assert/strict";
import {comparisonInputs} from "./comparison.js";
import type {RemotePlan} from "./remote-contract.js";
import type {ConnectedInput} from "./reuse-input.js";

export function remoteInputs(plan: RemotePlan) {
  if (plan.load === "single") {
    return comparisonInputs("single").map((s) =>
      ({...s, sourceSeasonID: s.seasonID}));
  }
  const sources = comparisonInputs("six");
  let cursor = 0;
  return [..."ABCDEFGHIJ"].flatMap((brand, index) =>
    Array.from({length: index === 0 ? 8 : index === 1 ? 2 : 1}, (_, slot) => {
      const sourceSeasonID = sources[cursor++ % sources.length].seasonID;
      const id = `virtual-${brand}-${slot + 1}-${sourceSeasonID}`;
      return {id, seasonID: id, brandID: `virtual-${brand}`, sourceSeasonID};
    }));
}

// URL과 golden은 유지하되 각 가상 작업의 입력과 저장 식별자를 분리한다.
export function remoteInputForPlan(base: ConnectedInput, plan: RemotePlan):
ConnectedInput {
  const items = remoteInputs(plan);
  const copy = <T extends {seasonID: string}>(rows: T[]) =>
    items.map((item) => {
      const source = rows.find((row) => row.seasonID === item.sourceSeasonID);
      assert.ok(source, `원본 시즌 누락: ${item.sourceSeasonID}`);
      return {...structuredClone(source), seasonID: item.id};
    });
  return {...base, seasons: copy(base.seasons), covers: copy(base.covers),
    golden: copy(base.golden)};
}
