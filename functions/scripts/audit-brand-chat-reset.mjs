import {writeFile} from "node:fs/promises";
import {auditBrandChatReset} from "./brand-chat-reset-support.mjs";

function parseArguments(argv) {
  let projectID = null;
  let outputPath = null;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--project") {
      projectID = argv[index + 1] ?? null;
      index += 1;
    } else if (argument === "--output") {
      outputPath = argv[index + 1] ?? null;
      index += 1;
    } else {
      throw new Error(`지원하지 않는 인자입니다: ${argument}`);
    }
  }
  if (!projectID?.trim()) {
    throw new Error("--project 값이 필요합니다.");
  }
  return {projectID: projectID.trim(), outputPath};
}

const {projectID, outputPath} = parseArguments(process.argv.slice(2));
const manifest = await auditBrandChatReset(projectID);
const serialized = `${JSON.stringify(manifest, null, 2)}\n`;
console.log(serialized.trimEnd());
console.log("dry-run 완료: Firebase/Storage/Cloud Tasks를 변경하지 않았습니다.");

if (outputPath) {
  await writeFile(outputPath, serialized, {encoding: "utf8", flag: "wx"});
  console.log(`manifest 저장 완료: ${outputPath}`);
}
