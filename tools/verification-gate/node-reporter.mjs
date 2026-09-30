import {resolve} from "node:path";
import {inspect} from "node:util";

// Node TestsStream의 판정에 필요한 필드만 JSON Lines로 기록한다.
export default async function* gateReporter(source) {
  for await (const event of source) {
    const {type, data = {}} = event;
    if (type === "test:pass" || type === "test:fail") {
      yield JSON.stringify({
        type,
        name: data.name,
        file: data.file ? resolve(data.file) : null,
        nesting: data.nesting,
        suite: data.details?.type === "suite",
        skip: data.skip ?? null,
        todo: data.todo ?? null,
        error: data.details?.error ? inspect(data.details.error, {depth: 8}) : null,
      }) + "\n";
    } else if (type === "test:summary") {
      yield JSON.stringify({type, counts: data.counts ?? null}) + "\n";
    } else if (["test:stdout", "test:stderr", "test:diagnostic"].includes(type)) {
      yield JSON.stringify({type, message: data.message, file: data.file}) + "\n";
    }
  }
}
