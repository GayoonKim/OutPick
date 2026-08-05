#!/usr/bin/env node
import {parseArguments} from "./arguments.js";
import {callIssueOperations, formatResult} from "./client.js";
import {resolveInvocation} from "./gcloud.js";

try {
  const command = parseArguments(process.argv.slice(2));
  const invocation = resolveInvocation(command.environment, command.endpoint);
  const body = await callIssueOperations({
    command,
    uri: invocation.uri,
    token: invocation.token,
  });
  process.stdout.write(`${formatResult(body, command.json)}\n`);
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}
