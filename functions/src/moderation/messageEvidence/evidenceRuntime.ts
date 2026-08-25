/* eslint-disable require-jsdoc, max-len */
export function messageEvidenceRuntimeForEnvironment(environment: NodeJS.ProcessEnv = process.env): {
  projectID: "outpick-test" | "outpick-664ae";
  serviceAccountEmail: string;
  maxInstances: 1 | 2;
} {
  const projectID = environment.GCLOUD_PROJECT?.trim() ||
    environment.GOOGLE_CLOUD_PROJECT?.trim() ||
    environment.GCP_PROJECT?.trim();
  if (projectID === "outpick-test") {
    return {projectID, serviceAccountEmail: "outpick-msg-evidence-dev@outpick-test.iam.gserviceaccount.com", maxInstances: 1};
  }
  if (projectID === "outpick-664ae") {
    return {projectID, serviceAccountEmail: "outpick-msg-evidence-prod@outpick-664ae.iam.gserviceaccount.com", maxInstances: 2};
  }
  throw new Error("unsupported_message_evidence_project");
}
