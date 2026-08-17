import { loadDeployment } from "./deployment.js";
import { runPollCycle } from "./keeper.js";
import { operatorAccount } from "./chain.js";

const POLL_INTERVAL_MS = 15_000;

const indexerUrl = process.env.INDEXER_URL;
if (!indexerUrl) {
  throw new Error("INDEXER_URL is not set");
}

function main(): void {
  const deployment = loadDeployment();

  console.log(`[keeper-bot] Operator: ${operatorAccount.address}`);
  console.log(`[keeper-bot] Watching OrderKeeper at ${deployment.OrderKeeper}`);
  console.log(`[keeper-bot] Polling ${indexerUrl} every ${POLL_INTERVAL_MS / 1000}s`);

  const interval = setInterval(() => {
    runPollCycle(deployment.OrderKeeper, indexerUrl!).catch((error) => {
      // runPollCycle already catches and logs everything it knows how to
      // handle — anything reaching here is unexpected, but the loop must
      // keep running regardless.
      console.error("[keeper-bot] Unexpected error in poll cycle:", error);
    });
  }, POLL_INTERVAL_MS);

  const shutdown = () => {
    console.log("[keeper-bot] Shutting down.");
    clearInterval(interval);
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main();
