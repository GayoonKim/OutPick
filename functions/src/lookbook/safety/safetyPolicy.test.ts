import assert from "node:assert/strict";
import test from "node:test";
import {commentReportDocumentID} from "./functions.js";

test("동일 신고는 deterministic document ID로 멱등 처리한다", () => {
  assert.equal(
    commentReportDocumentID("u", "comment", "b", "s", "p", "c"),
    "u__comment__b__s__p__c"
  );
});
