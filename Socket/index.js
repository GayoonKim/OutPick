import { PORT } from "./src/config.js";
import { createProductionDependencies } from "./src/app/createProductionDependencies.js";
import { createSocketApplication } from "./src/app/createSocketApplication.js";
import { initializeFirebaseAdmin } from "./src/firebaseAdmin.js";
import { createSystemClock } from "./src/runtime/systemClock.js";

const { admin, db } = initializeFirebaseAdmin();
const clock = createSystemClock();

const application = createSocketApplication({
  clock,
  createDependencies: ({ io }) => createProductionDependencies({
    admin,
    db,
    clock,
    io,
    env: process.env
  })
});

function startServer() {
  application.server.listen(PORT, () => {
    console.log(`server running at http://0.0.0.0:${PORT}`);
  });
}

process.on("SIGTERM", () => application.shutdownController.shutdown("SIGTERM"));
process.on("SIGINT", () => application.shutdownController.shutdown("SIGINT"));

application.server.on("error", (error) => {
  console.error("[server] listen error:", error);
  process.exit(1);
});

application.fetchRoomsFromFirebase().then(() => {
  console.log("All rooms initialized and ready:", Object.keys(application.rooms));
  startServer();
}).catch((error) => {
  console.error("Failed to fetch rooms from Firebase:", error);
  startServer();
});
