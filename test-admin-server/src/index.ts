import {loadConfig} from "./config.js";
import {makeApp} from "./app.js";
import {initializeFirebaseAdmin} from "./firebaseAdmin.js";

const config = loadConfig();
const firebaseAdmin = initializeFirebaseAdmin(config);
const app = makeApp(config, firebaseAdmin);

app.listen(config.port, config.host, () => {
  console.log(
    `OutPick Test Admin Server listening on http://${config.host}:${config.port}`
  );
});
