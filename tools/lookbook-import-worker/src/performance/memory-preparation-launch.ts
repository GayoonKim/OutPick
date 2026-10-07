import {readFile} from "node:fs/promises";
import {runPreparationCampaign} from "./memory-preparation-host.js";

const [sourcePath, inputDirectory, outputDirectory] = process.argv.slice(2);
const source = JSON.parse(await readFile(sourcePath, "utf8"));
const summary = await runPreparationCampaign(source, inputDirectory,
  outputDirectory);
console.log(JSON.stringify({verdict: summary.verdict, outputDirectory,
  halted: summary.halted}));
if (summary.verdict !== "passed") process.exitCode = 1;
