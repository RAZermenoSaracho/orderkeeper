import { loadDeployment } from "./deployment.js";
import { runPollCycle } from "./keeper.js";
import { operatorAccount } from "./chain.js";
import { startPollLoop } from "./pollLoop.js";

const POLL_INTERVAL_MS = 15_000;

const indexerUrl = process.env.INDEXER_URL;
if (!indexerUrl) {
  throw new Error("INDEXER_URL is not set");
}

async function main(): Promise<void> {
  const deployment = loadDeployment();

  console.log(`[keeper-bot] Operator: ${operatorAccount.address}`);
  console.log(`[keeper-bot] Watching OrderKeeper at ${deployment.OrderKeeper}`);
  console.log(`[keeper-bot] Polling ${indexerUrl} every ${POLL_INTERVAL_MS / 1000}s`);

  const stopPolling = startPollLoop(
    () => runPollCycle(deployment.OrderKeeper, indexerUrl!),
    POLL_INTERVAL_MS,
    (error) => {
      // runPollCycle already catches and logs everything it knows how to
      // handle — anything reaching here is unexpected, but the loop must
      // keep running regardless.
      console.error("[keeper-bot] Unexpected error in poll cycle:", error);
    },
  );

  const shutdown = () => {
    console.log("[keeper-bot] Shutting down.");
    stopPolling();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((error) => {
  // Anything reaching here is a startup failure (e.g. loadDeployment()
  // throwing) — matching order-indexer/src/index.ts's pattern.
  console.error("[keeper-bot] Fatal error during startup:", error);
  process.exit(1);
});
