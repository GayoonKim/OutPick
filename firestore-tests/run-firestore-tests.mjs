import { existsSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const environment = { ...process.env };
const configuredJava = spawnSync("java", ["-version"], {
  env: environment,
  stdio: "ignore",
});

if (configuredJava.status !== 0) {
  const javaHomes = [
    environment.JAVA_HOME,
    "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
    "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home",
  ].filter(Boolean);
  const javaHome = javaHomes.find((candidate) => existsSync(join(candidate, "bin", "java")));

  if (!javaHome) {
    console.error("Firestore Emulator 실행에 필요한 Java Runtime을 찾지 못했습니다.");
    process.exit(1);
  }

  environment.JAVA_HOME = javaHome;
  environment.PATH = `${join(javaHome, "bin")}:${environment.PATH ?? ""}`;
}

const result = spawnSync(
  "firebase",
  [
    "emulators:exec",
    "--only",
    "firestore",
    "--project",
    "outpick-rules-test",
    "node --test room-document-id.rules.test.mjs",
  ],
  {
    env: environment,
    stdio: "inherit",
  },
);

if (result.error) {
  throw result.error;
}
process.exit(result.status ?? 1);
