import {rm} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const scriptsDirectory = dirname(fileURLToPath(import.meta.url));
const libDirectory = resolve(scriptsDirectory, "../lib");

await rm(libDirectory, {recursive: true, force: true});
