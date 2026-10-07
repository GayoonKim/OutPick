/* eslint-disable require-jsdoc */
import {isAlreadyExistsError} from "../../core/errors.js";
import type {BatchDispatchIntent} from "./queue/dispatch.js";

type BatchTaskRequest = {
  parent: string;
  task: {
    name: string;
    dispatchDeadline: {seconds: number};
    httpRequest: {
      httpMethod: "POST";
      url: string;
      headers: Record<string, string>;
      body: Buffer;
      oidcToken: {serviceAccountEmail: string; audience: string};
    };
  };
};
type BatchTaskClient = {
  createTask: (request: BatchTaskRequest) => Promise<unknown>;
};
export type BatchTaskConfiguration = {
  projectID: string; locationID: string; queueID: string;
  workerURL: string; serviceAccountEmail: string; audience: string;
};

// maintenance-functions가 이 adapter를 Cloud Tasks client/config와 연결한다.
// 에뮬레이터에서는 주입한 client로 intent/task 계약만 확인한다.
export function batchTaskSender(
  client: BatchTaskClient, config: BatchTaskConfiguration
): (intent: BatchDispatchIntent) => Promise<void> {
  const worker = new URL(config.workerURL);
  const audience = new URL(config.audience);
  const sameOrigin = audience.origin === worker.origin;
  // 태그 URL은 특정 revision으로 라우팅하고, ID token은 안정된 서비스 URL을
  // audience로 사용한다. Cloud Run의 TAG---SERVICE URL만 이 조합을 허용한다.
  const taggedServiceURL =
    worker.hostname.endsWith("---" + audience.hostname) &&
    worker.hostname.endsWith(".run.app") &&
    audience.hostname.endsWith(".run.app");
  if (worker.protocol !== "https:" || worker.username || worker.password ||
      worker.pathname !== "/" || worker.search || worker.hash ||
      audience.protocol !== "https:" || audience.username ||
      audience.password ||
      audience.pathname !== "/" || audience.search || audience.hash ||
      (!sameOrigin && !taggedServiceURL) ||
      !config.serviceAccountEmail) throw new Error("INVALID_TASK_CONFIG");
  const parent = `projects/${config.projectID}/locations/${config.locationID}` +
    `/queues/${config.queueID}`;
  return async (intent) => {
    try {
      await client.createTask({
        parent,
        task: {
          name: `${parent}/tasks/${intent.taskID}`,
          dispatchDeadline: {seconds: intent.dispatchDeadlineSeconds},
          httpRequest: {
            httpMethod: "POST",
            url: `${worker.origin}${intent.endpoint}`,
            headers: {"Content-Type": "application/json"},
            body: Buffer.from(JSON.stringify(intent.payload)),
            oidcToken: {
              serviceAccountEmail: config.serviceAccountEmail,
              audience: config.audience,
            },
          },
        },
      });
    } catch (error) {
      if (!isAlreadyExistsError(error)) throw error;
    }
  };
}
