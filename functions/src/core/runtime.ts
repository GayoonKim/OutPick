import {setGlobalOptions} from "firebase-functions";

setGlobalOptions({maxInstances: 10});

export const FUNCTIONS_REGION = "asia-northeast3";
