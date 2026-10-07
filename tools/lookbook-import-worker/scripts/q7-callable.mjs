const ALLOWED = new Set(["createBrand", "requestSeasonCandidateImportJobs",
  "getSeasonImportBatch", "getLookbookExtractionReview", "reviewLookbookExtraction",
  "getSeasonImportFailures", "requestSeasonImportFailureRetry", "dismissSeasonImportFailure"]);

export function createQ7Callable({getToken, fetchImpl = fetch,
  projectID = "outpick-test", region = "asia-northeast3", onDispatch}) {
  if (projectID !== "outpick-test" || region !== "asia-northeast3") {
    throw new Error("Q7_TARGET_NOT_ALLOWED");
  }
  return async function call(name, data, {signal} = {}) {
    if (!ALLOWED.has(name)) throw new Error("Q7_CALLABLE_NOT_ALLOWED");
    const {idToken, uid} = await getToken();
    if (!idToken || !uid) throw new Error("Q7_LOGIN_REQUIRED");
    const url = "https://" + region + "-" + projectID +
      ".cloudfunctions.net/" + name;
    await onDispatch?.({name, requestID: data.requestID ?? null, recordedAt: Date.now()});
    const response = await fetchImpl(url, {method: "POST",
      headers: {"content-type": "application/json", authorization: "Bearer " + idToken},
      body: JSON.stringify({data}), signal: signal ?? AbortSignal.timeout(120_000)});
    let body;
    try { body = await response.json(); } catch {
      throw new Error("Q7_CALLABLE_INVALID_JSON");
    }
    if (!response.ok || body?.error) {
      const code = typeof body?.error?.status === "string" ?
        body.error.status : "HTTP_" + response.status;
      const error = new Error("Q7_CALLABLE_" + code);
      error.code = code;
      throw error;
    }
    if (!Object.hasOwn(body ?? {}, "result")) throw new Error("Q7_CALLABLE_INVALID_ENVELOPE");
    return body.result;
  };
}

export const q7AllowedCallables = Object.freeze([...ALLOWED]);
