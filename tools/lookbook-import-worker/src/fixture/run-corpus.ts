import {join} from "node:path";

import {evaluateFixtureCorpus} from "./corpus.js";

const fixtureRoot = join(process.cwd(), "fixtures");
const evaluations = await evaluateFixtureCorpus(fixtureRoot);
const failed = evaluations.filter((evaluation) => !evaluation.passed);

console.log(JSON.stringify({
  fixtureCount: evaluations.length,
  passedCount: evaluations.length - failed.length,
  failedCount: failed.length,
  evaluations,
}, null, 2));

if (failed.length > 0) {
  process.exitCode = 1;
}
