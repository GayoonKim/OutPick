/* eslint-disable max-len, require-jsdoc */
import {defineString} from "firebase-functions/params";

const SERVICE_ACCOUNT_ENV_KEY =
  "OUTPICK_AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL";
export const AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN =
  /^(?:outpick-auth-functions-dev@outpick-test|outpick-auth-functions-prod@outpick-664ae)\.iam\.gserviceaccount\.com$/;

export const authFunctionsServiceAccountEmail = defineString(
  SERVICE_ACCOUNT_ENV_KEY,
  {
    description: "Runtime service account for authentication Functions.",
    input: {
      text: {
        validationRegex: AUTH_FUNCTIONS_SERVICE_ACCOUNT_EMAIL_PATTERN,
        validationErrorMessage:
          "Enter an approved OutPick auth Functions service account email.",
      },
    },
  }
);
